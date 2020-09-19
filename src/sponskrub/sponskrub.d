/*
 This file is part of SponSkrub.

 SponSkrub is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 SponSkrub is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with SponSkrub.  If not, see <https://www.gnu.org/licenses/>.
*/
import std.stdio;
import std.algorithm;
import std.conv;
import std.string;
import std.math;
import std.range;
import std.array;
import core.sys.posix.signal;

import ffwrap;
import sponsorblock;
import args;

int main(string[] args)
{
	Args parsed_arguments = new Args([
			new ArgTemplate("sponskrub"),
			new ArgTemplate("video_id"),
			new ArgTemplate("input_filename"),
			new ArgTemplate("output_filename"),
			new ArgTemplate("chapter", true),
			new ArgTemplate("h", true),
			new ArgTemplate("exclude-sponsors", true),
			new ArgTemplate("include-intros", true),
			new ArgTemplate("include-outros", true),
			new ArgTemplate("include-interactions", true),
			new ArgTemplate("include-selfpromo", true),
			new ArgTemplate("include-music", true),
		]);
		
	parsed_arguments.parse(args);
	
	if (parsed_arguments.get_missing_arguments().length > 0) {
		writeln("Missing arguments: " ~ parsed_arguments.get_missing_arguments().join(" "));
		writeln();
	}
	
	if (parsed_arguments.unrecognised_arguments.length > 0) {
		writeln("Unrecognised arguments: " ~ parsed_arguments.unrecognised_arguments.join(" "));
		writeln();
	}
		
	if ("h" in parsed_arguments.flag_arguments || parsed_arguments.unrecognised_arguments.length > 0 || parsed_arguments.get_missing_arguments().length > 0) {
		writeln(
"Usage: sponskrub [-h] [-chapter] [-exclude-sponsors] [-include-intros] [-include-interactions] [-include-selfpromo] [-include-music] video_id input_filename output_filename

SponSkrub is an application for removing sponsors from downloaded Youtube video
 files, it requires an internet connection in order to consult the SponsorBlock
 database and ffmpeg must be installed.

Options:
 -h
   Display this help string

 -chapter
	 Mark sponsor spots as chapters rather than removing them.
	 Faster but leads to bigger file sizes
 
 -exclude-sponsors
   Exclude sponsors from the categories to be cut or marked as chapters

 -include-intros
   Cut or mark as chapters introductions (e.g: 'welcome to my video!')

 -include-interactions
   Cut or mark as chapters interactions (e.g: 'like this video if you liked it!')
 
 -include-selfpromo
   Cut or mark as chapters self promotion (e.g: 'visit our merch store')
 
 -include-music
   Cut or mark as chapters portions of the video with music but no content
");
		return 1;
	}
	
	auto video_id = parsed_arguments.positional_arguments[1];
	auto input_filename = parsed_arguments.positional_arguments[2];
	auto output_filename = parsed_arguments.positional_arguments[3];

	auto video_length = get_video_duration(input_filename);
	if (video_length is null) {
		writeln("Could not get video duration, is ffmpeg installed?");
		return 2;
	}
	writeln("Downloading video sponsor data");
	ClipTime[] sponsor_times;

	Categories[] categories = categories_from_arguments(parsed_arguments);
	
	if (categories.length == 0) {
		writeln("No categories were specified");
		return 4;
	} else {
		try {
			sponsor_times = get_video_skip_times(video_id, categories);
		}	catch (std.net.curl.HTTPStatusException e) {
			if (e.status == 404) {
				writeln("This video has no ad information available, either it has no ads or no one has logged any on SponsorBlock yet.");
			} else {
				writeln("Got %s the server must be broken, try again later".format(e.status));
			}
			return 3;
		}
		

		if (sponsor_times.length > 0) {		
			bool ffmpeg_status;
			
			auto content_times = timestampsToKeep(sponsor_times, video_length);
			
			if ("chapter" in parsed_arguments.flag_arguments) {
				writeln("Marking the shilling...");

				ffmpeg_status = add_ffmpeg_metadata(
					input_filename,
					output_filename,
					generate_chapters_metadata(sponsor_times, content_times)
				);
			} else {
				writeln("Surgically removing the shilling...");
				
				ffmpeg_status = run_ffmpeg_filter(
					input_filename,
					output_filename,
					cut_and_cat_clips_filter(content_times)
				);
			}
			
			if (ffmpeg_status) {
				writeln("Done!");
				return 0;
			} else {
				writeln("There was an issue generating the output file, is ffmpeg installed? This could be a bug");
				return 2;
			}			
		} else {
			writeln("Nothing to be done.");
			return 3;
		}
	}
}

//If the video has chapters this may overwrite them, although it doesn't look
//youtube downloader is adding them yet so who cares
string generate_chapters_metadata(ClipTime[] sponsor_times, ClipTime[] content_times) {
	return ";FFMETADATA1\n" ~
		content_times.map!(x => format_chapter_metadata(x.start, x.end, "Content")).join("\n")~
		"\n"~
		sponsor_times.map!(x => format_chapter_metadata(x.start, x.end, x.category)).join("\n");
}

string format_chapter_metadata(string start, string end, string title) {
	return ("[CHAPTER]\n"~
		"TIMEBASE=1/1\n"~
		"START=%s\n"~
		"END=%s\n"~
		"title=%s\n").format(start,end,title);
}


ClipTime[] timestampsToKeep(ClipTime[] sponsor_times, string video_length) {
	ClipTime[] clip_times;
	//If the sponsorship is directly at the beginning don't both adding content
	if (sponsor_times[0].start != "0.000000") {
		clip_times ~= ClipTime("0", sponsor_times[0].start, "Content");
	}

	sponsor_times.sort!((a, b) => a.start.to!float < b.start.to!float);
	
	for (auto i = 0; i < sponsor_times.length; i++) {
		auto clip_start = "";
		auto clip_end = "";
		clip_start = sponsor_times[i].end;
		if (i+1 < sponsor_times.length) {
			clip_end = sponsor_times[i+1].start;
		} else {
			clip_end = video_length;
		}
		clip_times ~= ClipTime(clip_start, clip_end, "Content");
	}

	return clip_times;
}

string cut_and_cat_clips_filter(ClipTime[] timestamps) {
	auto clip_indexes = iota(0, timestamps.length);

	auto filter =
		"[0:v]split = %s%s,[0:a]asplit = %s%s,%s%sconcat=n=%s:v=1:a=1[v][a]"
		.format(
			timestamps.length,
			clip_indexes.map!(i => "[vcopy%s]".format(i)).join,
			timestamps.length,
			clip_indexes.map!(i => "[acopy%s]".format(i)).join,
			timestamps.enumerate(0).map!(x => cut_audio_video_clip_filter(x.index, x.value.start, x.value.end)).join,
			clip_indexes.map!(i => "[v%s] [a%s] ".format(i,i)).join,
			timestamps.length
		);

	return filter;
}

string cut_audio_video_clip_filter(ulong stream_id, string start, string end) {
	return "[vcopy%s] trim=%s:%s,setpts=PTS-STARTPTS[v%s],[acopy%s] atrim=%s:%s,asetpts=PTS-STARTPTS[a%s],"
		.format(stream_id, start, end, stream_id, stream_id, start, end, stream_id);
}

Categories[] categories_from_arguments(Args arguments) {
	Categories[] categories = [];
	if ("exclude-sponsors" !in arguments.flag_arguments) {
		categories ~= Categories.Sponsor;
	}
	if ("include-intros" in arguments.flag_arguments) {
		categories ~= Categories.Intro;
	}
	if ("include-outros" in arguments.flag_arguments) {
		categories ~= Categories.Outro;
	}
	if ("include-interactions" in arguments.flag_arguments) {
		categories ~= Categories.Interaction;
	}
	if ("include-selfpromo" in arguments.flag_arguments) {
		categories ~= Categories.SelfPromo;
	}
	if ("include-music" in arguments.flag_arguments) {
		categories ~= Categories.Music;
	}
	
	return categories;
}
