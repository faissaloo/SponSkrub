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
import chapter;

ClipChapterTime[] timestamps_to_keep(ClipChapterTime[] chapters) {
	return chapters
		.sort!((a, b) => a.start.to!float < b.start.to!float)
		.filter!(chapter => chapter.category == Categories.Content)
		.array;
}

ClipChapterTime[] calculate_timestamps_for_kept_clips(ClipChapterTime[] chapters) {
	auto current_time = "0";
	ClipChapterTime[] adjusted_chapters = [];
	
	foreach (ClipChapterTime chapter; chapters) {
		auto duration = chapter.end.to!float - chapter.start.to!float;
		auto end_time = (current_time.to!float + duration).to!string; // I really need to deal with this bouncing between strings and floats nonsense
		adjusted_chapters ~= ClipChapterTime(current_time, end_time, chapter.category, chapter.title);
		current_time = end_time;
	}
	return adjusted_chapters;
	
}

string cut_and_cat_clips_filter(ClipChapterTime[] timestamps, FileCategory category) {
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
