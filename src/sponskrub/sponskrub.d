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
import std.typecons;
import std.datetime;
import std.file;

import core.sys.posix.signal;

import ffwrap;
import sponsorblock;
import args;
import chapter;
import cut;

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
			new ArgTemplate("include-nonmusic", true),
			new ArgTemplate("no-id", true),
			new ArgTemplate("force-http", true),
			new ArgTemplate("keep-date", true),
			new ArgTemplate("api-url", true, false, 1),
			new ArgTemplate("proxy", true, false, 1),
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
"Usage: sponskrub [-h] [-chapter] [-exclude-sponsors] [-include-intros] [-include-outros] [-include-interactions] [-include-selfpromo] [-include-nonmusic] [-keep-date] [-proxy proxy] [-api-url url] video_id input_filename output_filename

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

 -include-outros
   Cut or mark as chapters outros (e.g: 'see you next week')

 -include-interactions
   Cut or mark as chapters interactions (e.g: 'like this video if you liked it!')
 
 -include-selfpromo
   Cut or mark as chapters self promotion (e.g: 'visit our merch store')
 
 -include-nonmusic
   Cut or mark as chapters portions of music videos without music

 -api-url
   Specify the url where the API is located, defaults to sponsor.ajay.app
 
 -no-id
   Searches for sponsor data by the partial hash of the video id instead of
	 directly requesting it.
	 This adds a degree of privacy, but is slightly slower and uses more bandwidth.
 
 -keep-date
   Give the output file the same modification date as the input file.

 -proxy
   Allows you to specify a proxy to route any requests through

 -force-http
   By default sponskrub connects to the API via HTTPS, use this to force HTTP
");
		return 1;
	}
	
	bool force_http = false;
	if ("force-http" in parsed_arguments.flag_arguments) {
		force_http = true;
	}
	
	string api_url;
	if ("api-url" in parsed_arguments.flag_arguments) {
		api_url = parsed_arguments.flag_arguments["api-url"].join;
	} else {
		api_url = "sponsor.ajay.app";
	}
	
	string proxy;
	if ("proxy" in parsed_arguments.flag_arguments) {
		proxy = parsed_arguments.flag_arguments["proxy"].join;
	} else {
		proxy = "";
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
			if ("no-id" in parsed_arguments.flag_arguments) {
				sponsor_times = get_video_skip_times_private(video_id, categories, api_url, proxy, force_http);
			} else {
				sponsor_times = get_video_skip_times_direct(video_id, categories, api_url, proxy, force_http);
			}
		}	catch (std.net.curl.HTTPStatusException e) {
			if (e.status == 404) {
				writeln("This video has no ad information available, either it has no ads or no one has logged any on SponsorBlock yet.");
			} else {
				writeln("Got %s the server must be broken, try again later".format(e.status));
			}
			return 3;
		} catch (std.net.curl.CurlException e) {
			writeln("Couldn't connect to the Sponsorblock API");
			if (proxy != "") {
				writeln("Ensure your proxy is correctly configured");
			}
			if (api_url != "sponsor.ajay.app") {
				writeln("Make sure the specified api url is correct");
			}
		}

		if (sponsor_times.length > 0) {		
			bool ffmpeg_status;
			
			ChapterTime[] chapter_times; 
			ClipChapterTime[] new_chapter_times;
			
			chapter_times = get_chapter_times(input_filename);
			auto input_chapters_count = chapter_times.length;
			if (input_chapters_count == 0) {
				chapter_times = [ChapterTime("0", video_length, "sponskrub-content")];
			}
			
			new_chapter_times = merge_sponsor_times_with_chapters(sponsor_times, chapter_times);
			
			if ("chapter" in parsed_arguments.flag_arguments) {
				writeln("Marking the shilling...");
				
				ffmpeg_status = add_ffmpeg_metadata(
					input_filename,
					output_filename,
					generate_chapters_metadata(new_chapter_times)
				);
			} else {
				writeln("Surgically removing the shilling...");
				auto content_times = timestamps_to_keep(new_chapter_times);
				auto cut_chapter_times = "";
				
				if (input_chapters_count > 0) {
					cut_chapter_times = generate_chapters_metadata(calculate_timestamps_for_kept_clips(content_times));
				}
				
				ffmpeg_status = run_ffmpeg_filter(
					input_filename,
					output_filename,
					cut_and_cat_clips_filter(content_times, get_file_category(input_filename)),
					get_file_category(input_filename),
					cut_chapter_times
				);
			}
			
			if (ffmpeg_status) {
				if ("keep-date" in parsed_arguments.flag_arguments) {
					copy_file_modified_time(input_filename, output_filename);
				}
				
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
	if ("include-nonmusic" in arguments.flag_arguments) {
		categories ~= Categories.NonMusic;
	}
	
	return categories;
}

void copy_file_modified_time(string source, string destination) {
	SysTime accessTime, modificationTime;
	getTimes(source, accessTime, modificationTime);
	setTimes(destination, accessTime, modificationTime);
}
