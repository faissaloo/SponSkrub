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
import sponsorblock;
import ffwrap;

ClipTime[] timestamps_to_keep(ClipTime[] sponsor_times, string video_length) {
	ClipTime[] clip_times;
	sponsor_times.sort!((a, b) => a.start.to!float < b.start.to!float);
	
	//If the sponsorship is directly at the beginning don't add both content and the sponsor
	if (sponsor_times[0].start != "0.000000") {
		clip_times ~= ClipTime("0", sponsor_times[0].start, "content");
	}

	
	for (auto i = 0; i < sponsor_times.length; i++) {
		auto clip_start = "";
		auto clip_end = "";
		clip_start = sponsor_times[i].end;
		if (i+1 < sponsor_times.length) {
			clip_end = sponsor_times[i+1].start;
		} else {
			clip_end = video_length;
		}
		clip_times ~= ClipTime(clip_start, clip_end, "content");
	}

	return clip_times;
}

string cut_and_cat_clips_filter(ClipTime[] timestamps, FileCategory category) {
  timestamps.sort!((a, b) => a.start.to!float < b.start.to!float);

	auto clip_indexes = iota(0, timestamps.length);

	string filter;
  if (category == FileCategory.AUDIO_VIDEO) {
    filter = "[0:v]split = %s%s,[0:a]asplit = %s%s,%s%sconcat=n=%s:v=1:a=1[v][a]"
      .format(
        timestamps.length,
        clip_indexes.map!(i => "[vcopy%s]".format(i)).join,
        timestamps.length,
        clip_indexes.map!(i => "[acopy%s]".format(i)).join,
        timestamps.enumerate(0).map!(x => cut_audio_video_clip_filter(x.index, x.value.start, x.value.end)).join,
        clip_indexes.map!(i => "[v%s] [a%s] ".format(i,i)).join,
        timestamps.length
      );
  } else if (category == FileCategory.VIDEO) {
    filter = "[0:v]split = %s%s,%s%sconcat=n=%s:v=1[v]"
      .format(
        timestamps.length,
        clip_indexes.map!(i => "[vcopy%s]".format(i)).join,
        timestamps.enumerate(0).map!(x => cut_video_clip_filter(x.index, x.value.start, x.value.end)).join,
        clip_indexes.map!(i => "[v%s] ".format(i)).join,
        timestamps.length
      );
  } else if (category == FileCategory.AUDIO) {
    filter = "[0:a]asplit = %s%s,%s%sconcat=n=%s:v=0:a=1[a]"
      .format(
        timestamps.length,
        clip_indexes.map!(i => "[acopy%s]".format(i)).join,
        timestamps.enumerate(0).map!(x => cut_audio_clip_filter(x.index, x.value.start, x.value.end)).join,
        clip_indexes.map!(i => "[a%s] ".format(i)).join,
        timestamps.length
      );
  }

	return filter;
}

string cut_audio_clip_filter(ulong stream_id, string start, string end) {
	return "[acopy%s] atrim=%s:%s,asetpts=PTS-STARTPTS[a%s],"
		.format(stream_id, start, end, stream_id);
}

string cut_video_clip_filter(ulong stream_id, string start, string end) {
	return "[vcopy%s] trim=%s:%s,setpts=PTS-STARTPTS[v%s],"
		.format(stream_id, start, end, stream_id);
}

string cut_audio_video_clip_filter(ulong stream_id, string start, string end) {
	return cut_video_clip_filter(stream_id, start, end)~cut_audio_clip_filter(stream_id, start, end);
}
