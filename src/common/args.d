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
module args;
import std.container.array;
import std.stdio;
import std.typecons;
import std.algorithm;
import std.array;

class ArgTemplate {
  string name;
  bool required;
  bool flag;
  int subarguments;
  
  this(string name) {
    this.name = name;
    this.required = true;
    this.flag = false;
    this.subarguments = false;
  }
  
  this(string name, bool flag) {
    this.name = name;
    this.required = false;
    this.flag = flag;
    this.subarguments = false;
  }
  
  this(string name, bool flag, bool required, int subarguments) {
    this.name = name;
    this.flag = flag;
    this.required = required;
    this.subarguments = subarguments;
  }
}

class Args {
  ArgTemplate[] required_positional_argument_templates;
  ArgTemplate[string] required_flag_argument_templates;
  
  ArgTemplate[] positional_argument_templates;
  ArgTemplate[string] flag_argument_templates;
  
  string[] positional_arguments;
  string[][string] flag_arguments;
  
  string[] unrecognised_arguments;
  
  this(ArgTemplate[] args_templates) {
    foreach (ArgTemplate arg_template; args_templates) {
      if (arg_template.flag) {
        flag_argument_templates[arg_template.name] = arg_template;
        if (arg_template.required) {
          required_flag_argument_templates[arg_template.name] = arg_template;
        }
      } else {
        positional_argument_templates ~= arg_template;
        if (arg_template.required) {
          required_positional_argument_templates ~= arg_template;
        }
      }
    }
  }
  
  void parse(string[] args) {
    int remaining_subarguments = 0;
    bool force_positional_argument = false;
    string flag_name;
    
    foreach (string arg; args) {
      if (remaining_subarguments > 0) {
        flag_arguments[flag_name] ~= arg;
        remaining_subarguments--;
      } else if (arg == "--") {
        force_positional_argument = true;
      } else if (!force_positional_argument && arg[0] == '-') {
        flag_name = arg[1..$];
        if (flag_name in flag_argument_templates) {
          flag_arguments[flag_name] = [];
          if (flag_argument_templates[flag_name].subarguments > 0) {
            remaining_subarguments = flag_argument_templates[flag_name].subarguments;
          }
        } else {
          unrecognised_arguments ~= arg;
        }
      } else if (positional_arguments.length < positional_argument_templates.length) {
        positional_arguments ~= arg;
      } else {
        unrecognised_arguments ~= arg;
      }
    }
  }
  
  string[] get_missing_arguments() {
    string[] missing_arguments;
    
    foreach (string required_flag; required_flag_argument_templates.byKey()) {
      if (required_flag !in flag_arguments) {
        missing_arguments ~= required_flag;
      }
    }
    
    if (positional_arguments.length < required_positional_argument_templates.length) {
      missing_arguments ~= required_positional_argument_templates[positional_arguments.length..$].map!(x => x.name).array;
    }
    
    return missing_arguments;
  }
}
