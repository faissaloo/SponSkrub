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

module sponsorblock;
import std.typecons;
import std.net.curl;
import std.json;
import std.algorithm;
import std.string;
import std.array;
import std.conv;
import std.stdio;

enum Categories: string {
	Sponsor = "sponsor",
	Intro = "intro", 
	Outro = "outro",
	Interaction = "interaction",
	SelfPromo = "selfpromo",
	NonMusic = "music_offtopic"
}

alias ClipTime = Tuple!(string, "start", string, "end", string, "category");

string stringify_timestamp(JSONValue raw_timestamp) {
	double timestamp;
	if (raw_timestamp.type() == JSONType.integer) {
		timestamp = raw_timestamp.integer.to!float;
	} else if (raw_timestamp.type() == JSONType.float_){
		timestamp = raw_timestamp.floating;
	}
	return "%6f".format(timestamp);
}

ClipTime[] get_video_skip_times(string video_id, Categories[] categories, string api_url) {
	auto data = get("http://%s/api/skipSegments?videoID=%s&categories=%s".format(api_url, video_id, `["`~(cast(string[])categories).join(`", "`)~`"]`));
	auto json = parseJSON(data);
	//This array needs sorting or whatever so they get lined up properly
	//Or maybe we should get the thing that figures out the times to do that?
	return json.array.map!(
		clip_times => ClipTime(stringify_timestamp(clip_times["segment"][0]), stringify_timestamp(clip_times["segment"][1]), clip_times["category"].str)
	).array;
}
