import std.stdio;
import std.process;
import std.regex;
import std.array;
import std.format;
import std.string;
import std.path;
import std.file;

import args;

int main(string[] args) {
  Args parsed_arguments = new Args([
      new ArgTemplate("youtube-dl-sponsorblock"),
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
"Usage: youtube-dl-sponsorblock [-h] url_or_video_id [-dl-args args] [-skrub-args args]
youtube-dl-sponsorblock is a wrapper around sponskrub and youtube-dl that downloads a video then 
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
  
  
  auto youtube_url_regex = ctRegex!(r"^(?:(?:https?:\/\/)?(?:www\.)?youtu(?:\.be|be\.com)/watch\?.*v=)?([A-Za-z0-9_-]{11})");
  
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
    if (!download_video(video_url_or_id, dl_args)) {
      writeln("Some kind of error occured while downloading, this is probably something to do with youtube-dl");
    }
    return 2;
  }
  
  return 0;
}

auto get_download_filename(string video_id, string dl_args) {
  //This breaks with mkvs because youtube-dl's --get-filename is slightly broken
  //https://github.com/ytdl-org/youtube-dl/issues/5710
  //workaround is to only ever use the best of a single container by default
  auto youtube_dl_get_filename = executeShell(`youtube-dl -f 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo[ext=webm]+bestaudio[ext=webm]/best' %s --get-filename -- "%s"`.format(dl_args, video_id));
  if (youtube_dl_get_filename.status == 0) {
    return youtube_dl_get_filename.output.chomp;
  } else {
    writeln(youtube_dl_get_filename.output);
    return null;
  }
}

auto download_and_skrub(string video_id, string skrub_args, string dl_args) {
  auto filename = get_download_filename(video_id, dl_args);
  
  if (filename is null) {
    return false;
  } else {
    auto output_filename_parts = pathSplitter(filename).array;
    output_filename_parts[$-1] = "skrubbed-"~output_filename_parts[$-1];
    auto output_filename = buildPath(output_filename_parts);
    
    if (download_video(video_id, dl_args)) {
      if (skrub(video_id, filename, output_filename, skrub_args)) {
        remove(filename);
        return true;
      } else {
        //nothing to skrub, just move it
        rename(filename, output_filename);
        return true;
      }
    } else {
      return false;
    }
  }
}

auto skrub(string video_id, string input_filename, string output_filename, string skrub_args) {
  auto sponskrub_process = spawnShell(`sponskrub %s -- "%s" "%s" "%s"`.format(skrub_args, video_id, input_filename, output_filename));
  return wait(sponskrub_process) == 0;
}

auto download_video(string video_url_or_id, string dl_args) {
  auto youtube_dl_process = spawnShell(`youtube-dl -f 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo[ext=webm]+bestaudio[ext=webm]/best' %s -- "%s"`.format(dl_args, video_url_or_id));
  return wait(youtube_dl_process) == 0;
}
