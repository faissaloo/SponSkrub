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

import ffwrap;
import sponsorblock;
import stack;

alias ClipChapterTime = Tuple!(string, "start", string, "end", string, "category", string, "title");

//I need to come up with a way to implement this that's easier to understand
ClipChapterTime[] merge_sponsor_times_with_chapters(ClipTime[] sponsor_times, ChapterTime[] chapter_times) {
	sponsor_times.sort!((a, b) => a.start.to!float < b.start.to!float);
	chapter_times.sort!((a, b) => a.start.to!float < b.start.to!float);

	ClipChapterTime[] clip_chapters = [];
	Stack!(ClipTime) sponsor_stack = []; //stack used for storing sponsors that other sponsors are within
	auto sponsor_index = 0;
	auto chapter_index = 0;
	auto is_sponsor = false;
	string clip_terminal = "0";
	
	if (sponsor_times[sponsor_index].start.to!float == 0) {
		is_sponsor = true;
	}
	
	while (chapter_index < chapter_times.length) {
		if (is_sponsor) {
			//if the stack has items we need to create clips from where we are now to either the end of that sponsorship or the beginning of the next
			//I'd do !empty but idk how to override the UDA so I just renamed the method
			if (sponsor_stack.notEmpty()) {
				//we'll need to check if the next sponsorship begins before this one ends
				if (sponsor_times[sponsor_index].start.to!float < sponsor_stack.peek().end.to!float) {
					//	we need to create a chapter from here to the beginning of that sponsor
					//  we can then make that sponsor's beginning the clip_terminal methinks
					//  if that sponsor ends after this sponsor we can pop this sponsor
					clip_chapters ~= ClipChapterTime(clip_terminal, sponsor_times[sponsor_index].start, "sponskrub-" ~ sponsor_times[sponsor_index].category, "");
					clip_terminal = sponsor_times[sponsor_index].start;
					
					if (sponsor_times[sponsor_index].end.to!float > sponsor_stack.peek().end.to!float) {
						sponsor_stack.pop();
					}
				} else {
					//  we can just end and pop this sponsorship and set is_sponsor to false
					sponsor_stack.pop();
					is_sponsor = false;
				}
			}
			//If there isn't another sponsor starting within this sponsor
			//including if there are no other sponsors after this
			if ((sponsor_index+1 >= sponsor_times.length) || (sponsor_index+1 < sponsor_times.length && sponsor_times[sponsor_index].end.to!float < sponsor_times[sponsor_index+1].start.to!float)) {
				//we need a way to check if there is another sponsor starting within this sponsor
				//if that is the case we shouldn't set is_sponsor to false
				clip_chapters ~= ClipChapterTime(clip_terminal, sponsor_times[sponsor_index].end, "sponskrub-" ~ sponsor_times[sponsor_index].category, "");
				clip_terminal = sponsor_times[sponsor_index].end;
				sponsor_index++;
				is_sponsor = false;
			} else {
				//if there is another sponsor within this sponsor
				//add the current sponsor up to the next sponsor
				clip_chapters ~= ClipChapterTime(clip_terminal, sponsor_times[sponsor_index+1].start, "sponskrub-" ~ sponsor_times[sponsor_index].category, "");
				clip_terminal = sponsor_times[sponsor_index+1].start;
				
				if (sponsor_times[sponsor_index+1].end.to!float < sponsor_times[sponsor_index].end.to!float) {
					//if that sponsor ends before this sponsor ends we should push it to the stack
					sponsor_stack.push(sponsor_times[sponsor_index]);
				}
				
				//go to the next sponsor
				sponsor_index++;
			}
		} else {
			auto chapter_title = chapter_times[chapter_index].title;
			string next_terminal;
			if (sponsor_index < sponsor_times.length && sponsor_times[sponsor_index].start.to!float < chapter_times[chapter_index].end.to!float) {
				//lets end this chapter at the sponsor
				next_terminal = sponsor_times[sponsor_index].start;
				is_sponsor = true;
				//If this sponsor takes us beyond the clip move to the next clip
				if (sponsor_times[sponsor_index].end.to!float > chapter_times[chapter_index].end.to!float) {
					chapter_index++;
				}
			} else {
				//chapter doesn't have anymore sponsors
				next_terminal = chapter_times[chapter_index].end;
				chapter_index++;
			}
			clip_chapters ~= ClipChapterTime(clip_terminal, next_terminal, Categories.Content, chapter_title);
			clip_terminal = next_terminal;
		}
	}
	
	return clip_chapters;
}

string generate_chapters_metadata(ClipChapterTime[] chapter_times) {
	return ";FFMETADATA1\n" ~
		chapter_times.map!(
			x => format_chapter_metadata(x.start, x.end, x.title~x.category)
		).join("\n");
}

string format_chapter_metadata(string start, string end, string title) {
	return ("[CHAPTER]\n"~
		"TIMEBASE=1/1\n"~
		"START=%s\n"~
		"END=%s\n"~
		"title=%s\n").format(start,end,title);
}
