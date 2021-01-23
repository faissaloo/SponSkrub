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
import std.typecons;
import std.conv;
import std.process;
import std.string;
import std.mmfile;
import std.file;
import std.range;
import std.random;
import std.algorithm;
import std.json;

alias ChapterTime = Tuple!(string, "start", string, "end", string, "title");
enum FileCategory {
	AUDIO_VIDEO,
	VIDEO,
	AUDIO,
	OTHER
}

FileCategory get_file_category(string filename) {
	auto ffprobe_process = execute(["ffprobe", "-loglevel", "quiet", "-show_entries", "stream=codec_type", "-print_format", "default=noprint_wrappers=1:nokey=1", filename]);
	if (canFind(ffprobe_process.output, "video") && canFind(ffprobe_process.output, "audio")) {
		return FileCategory.AUDIO_VIDEO;
	} else if (canFind(ffprobe_process.output, "video")) {
		return FileCategory.VIDEO;
	} else if (canFind(ffprobe_process.output, "audio")) {
		return FileCategory.AUDIO;
	}
	return FileCategory.OTHER;
}
string get_video_duration(string filename) {
	auto ffprobe_process = execute(["ffprobe", "-loglevel", "quiet", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", filename]);

	if (ffprobe_process.status != 0) {
		return null;
	} else {
		return ffprobe_process.output.chomp;
	}
}

ChapterTime[] get_chapter_times(string filename) {
	auto ffprobe_process = execute(["ffprobe", "-loglevel", "quiet", "-show_chapters", "-print_format", "json", filename]);
	auto json = parseJSON(ffprobe_process.output);
	
	//D can't currently distinguish between null and [] so this'll just silently 
	//fail because I'm not writing hacks to get around broken language features
	if (ffprobe_process.status != 0) {
		return null;
	} else {
		return json["chapters"].array.map!(
			chapter_times => ChapterTime(chapter_times["start_time"].str, chapter_times["end_time"].str, chapter_times["tags"]["title"].str)
		).array;
	}
}
import std.stdio;

bool run_ffmpeg_filter(string input_filename, string output_filename, string filter, FileCategory category, string metadata = "") {
	string metadata_filename = null;
	scope(exit) {
		if (metadata_filename !is null) {
			remove(metadata_filename);
		}
	}
	
	string[] args;
	args = ["ffmpeg", "-loglevel", "warning", "-hide_banner", "-stats", "-i", input_filename];
	
	if (metadata != "") {
		metadata_filename = prepend_random_prefix(6, "-metadata.ffm");
		write_metadata(metadata_filename, metadata);
		args ~= ["-i", metadata_filename, "-map_metadata", "0", "-map_chapters", "1"];
	}
	
	if (category == FileCategory.AUDIO_VIDEO) {
		args ~= ["-filter_complex", filter, "-map", "[v]", "-map", "[a]", output_filename];
	} else if (category == FileCategory.VIDEO) {
		args ~= ["-filter_complex", filter, "-map", "[v]", output_filename];
	}	else if (category == FileCategory.AUDIO) {
		args ~= ["-filter_complex", filter, "-map", "[a]", output_filename];
	}
	auto ffmpeg_process = spawnProcess(args);
	return wait(ffmpeg_process) == 0;
}

bool add_ffmpeg_metadata(string input_filename, string output_filename, string metadata) {
	string metadata_filename = prepend_random_prefix(6, "-metadata.ffm");
	scope(exit) {
		remove(metadata_filename);
	}
	write_metadata(metadata_filename, metadata);
	
	auto ffmpeg_process = spawnProcess(["ffmpeg", "-loglevel", "warning", "-hide_banner", "-stats", "-i", input_filename, "-i", metadata_filename, "-map", "0", "-map_metadata", "0", "-map_chapters", "1", "-codec", "copy", output_filename]);
	auto result = wait(ffmpeg_process) == 0;
	
	return result;
}

auto write_metadata(string filename, string metadata) {
	auto file = new MmFile(filename, MmFile.Mode.readWriteNew, metadata.length+2, null);
	scope(exit) {
		destroy(file);
	}
	ubyte[] data = cast(ubyte[]) file[0..metadata.length];
	data[] = cast(ubyte[]) metadata[];
}

string prepend_random_prefix(int length, string suffix) {
	auto prefix = iota(length).map!((_) => "abcdefghijklmnopqrstuvwxyz0123456789"[uniform(0,$)]).array;
	return prefix ~ suffix;
}
