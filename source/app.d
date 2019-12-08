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

void main(string[] args)
{
	if (args.length < 4) {
		writeln(
"Usage: sponskrub video_id input_filename output_filename

SponSkrub is an application for removing sponsors from downloaded Youtube video
 files, it requires an internet connection in order to consult the SponsorBlock
  database and ffmpeg must be installed.");
		return;
	}
	auto video_id = args[1];
	auto input_filename = args[2];
	auto output_filename = args[3];

	auto video_length = get_video_duration(input_filename);
	if (video_length is null) {
		writeln("Could not get video duration, is ffmpeg installed?");
	}
	writeln("Downloading video sponsor data");
	ClipTime[] sponsorTimes;

	try {
		sponsorTimes = get_video_sponsor_times(video_id);
	}	catch (std.net.curl.HTTPStatusException e) {
		if (e.status == 404) {
			writeln("This video has no ad information available, either it has no ads or no one has logged any on SponsorBlock yet.");
		} else {
			writeln("Got %s the server must be broken, try again later".format(e.status));
		}
		return;
	}

	if (sponsorTimes.length > 0) {
		writeln("Surgically removing the shilling...");
		auto filter_status = run_ffmpeg_filter(input_filename, output_filename, cut_and_cat_clips_filter(timestampsToKeep(sponsorTimes, video_length)));
		if (filter_status) {
			writeln("Done!");
		} else {
			writeln("There was an issue generating the output file, is ffmpeg installed? This could be a bug");
		}
	} else {
		writeln("Nothing to be done.");
	}
}

ClipTime[] timestampsToKeep(ClipTime[] sponsorTimes, string video_length) {
	ClipTime[] clip_times = [ClipTime("0", sponsorTimes[0].start)];

	for (auto i = 0; i < sponsorTimes.length; i++) {
		auto clip_start = "";
		auto clip_end = "";
		clip_start = sponsorTimes[i].end;
		if (i+1 < sponsorTimes.length) {
			clip_end = sponsorTimes[i+1].start;
		} else {
			clip_end = video_length;
		}
		clip_times ~= ClipTime(clip_start, clip_end);
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
