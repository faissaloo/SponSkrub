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
module ffwrap;
import std.process;
import std.string;

string get_video_duration(string filename) {
	auto ffprobe_process = execute(["ffprobe", "-v", "quiet", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", filename]);

	if (ffprobe_process.status != 0) {
		return null;
	} else {
		return ffprobe_process.output.chomp;
	}
}

bool run_ffmpeg_filter(string input_filename, string output_filename, string filter) {
	auto ffmpeg_process = spawnProcess(["ffmpeg", "-i", input_filename, "-filter_complex", filter, "-map", "[v]", "-map", "[a]",output_filename]);
	return wait(ffmpeg_process) == 0;
}
