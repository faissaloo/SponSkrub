import std.stdio;
import std.process;
import std.regex;
import std.array;
import std.format;

import args;

int main(string[] args) {
  Args parsed_arguments = new Args([
      new ArgTemplate("ydl"),
      new ArgTemplate("url_or_video_id"),
      new ArgTemplate("h", true),
      new ArgTemplate("dl-args", true, false, 1),
      new ArgTemplate("skrub-args", true, false, 1),
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
"Usage: ydl [-h] url_or_video_id [-ydl-args args] [-skrub-args args]
ydl is a wrapper around sponskrub and youtube-dl that downloads a video then 
 automatically strips the sponsor spots out. If the video is not a YouTube video 
 it will simply be downloaded
Options:
  -h
    Display this help string

  -dl-args
    Append these arguments when executing youtube-dl
  
  -skrub-args
    Append these arguments when executing sponskrub
"
  );
    return 1;
  }


  auto dl_args = "";
  if ("dl-args" in parsed_arguments.flag_arguments) {
    dl_args = parsed_arguments.flag_arguments["dl-args"].join;
  }
  
  auto skrub_args = "";
  if ("skrub-args" in parsed_arguments.flag_arguments) {
    skrub_args = parsed_arguments.flag_arguments["skrub-args"].join;
  }
  
  
  auto youtube_url_regex = ctRegex!(r"^(?:(?:https?:\/\/)?(?:www\.)?youtu(?:\.be|be\.com)/watch\?.*v=)([A-Za-z0-9_-]{11})");
  
  auto video_url_or_id = parsed_arguments.positional_arguments[1];
  auto youtube_url_matcher = video_url_or_id.matchFirst(youtube_url_regex);
  
  if (!youtube_url_matcher.empty) {
    writeln("Youtube url specified");
    auto video_id = youtube_url_matcher[1];
    if (!download_and_skrub(video_id, skrub_args, dl_args)) {
      writeln("Some kind of error occured while downloading and skrubbing, this could be a bug");
      return 2;
    }
  } else {
    writeln("Non-youtube url specified");
    if (!download_only(video_url_or_id)) {
      writeln("Some kind of error occured while downloading, this is probably something to do with youtube-dl");
    }
    return 2;
  }
  
  return 0;
}

auto download_and_skrub(string video_id, string skrub_args, string dl_args) {
  auto youtube_dl_process = spawnShell(`youtube-dl -f 18 %s --exec "sponskrub %s '%s' {} skrubbed-{} && rm {} || mv {} skrubbed-{}" %s`.format(video_id, skrub_args, video_id, dl_args));
  return wait(youtube_dl_process) == 0;
}

auto download_only(string video_url) {
  auto youtube_dl_process = spawnShell(`youtube-dl %s`.format(video_url));
  return wait(youtube_dl_process) == 0;
}
