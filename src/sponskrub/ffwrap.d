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
import std.mmfile;
import std.file;
import std.range;
import std.random;
import std.algorithm;

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

bool add_ffmpeg_metadata(string input_filename, string output_filename, string metadata) {
	string metadata_filename = prepend_random_prefix(6, "-metadata.ffm");
	scope(exit) {
		remove(metadata_filename);
	}
	
	write_metadata(metadata_filename, metadata);
	auto ffmpeg_process = spawnProcess(["ffmpeg", "-i", input_filename, "-i", metadata_filename, "-map_metadata", "1", "-map_chapters", "1", "-vcodec", "copy", output_filename]);
	auto result = wait(ffmpeg_process) == 0;
	
	return result;
}

auto write_metadata(string filename, string metadata) {
	auto file = new MmFile(filename, MmFile.Mode.readWriteNew, metadata.length+2, null);
	ubyte[] data = cast(ubyte[]) file[0..metadata.length];
	data[] = cast(ubyte[]) metadata[];
}

string prepend_random_prefix(int length, string suffix) {
	auto prefix = iota(length).map!((_) => "abcdefghijklmnopqrstuvwxyz0123456789"[uniform(0,$)]).array;
	return prefix ~ suffix;
}
