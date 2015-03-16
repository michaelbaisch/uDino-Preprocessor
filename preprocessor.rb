#!/usr/bin/env ruby
# encoding: utf-8

require 'fileutils'
require 'shellwords'

# µDino preprocessor
# Inspired from https://github.com/ffissore/Arduino/blob/coanctags/arduino-core/src/processing/app/preproc/CTagsParser.java


orgctagsArguments = "-u --language-force=c++ -f - --c++-kinds=svpf --fields=KSTtzn"
ctagsArguments = "--language-force=c++ -f - --c++-kinds=pf --fields=KSTtzn"
fields = ['kind', 'line', 'typeref', 'signature', 'returntype']
knownTagKinds = ["prototype", "function"]
arduinoExtensions = "{*.ino,*.pde}"
otherExtensionsToCopy = "{*.cpp,*.c,*.h,*.S}"


if !(ARGV.length > 1)
  puts <<-EOF
Please define a project and output folder

Usage: ./preprocessor.rb project_folder output_folder

  EOF
  abort
end


projectFolder = ARGV.first.chomp
outputFolder = ARGV[1].chomp

# projectFolder and outputFolder should really be folders
if !File.directory?(projectFolder) || !File.directory?(outputFolder) then
  abort "Please define folders as arguments"
end

projectFolder << "/" if !projectFolder.end_with? "/"
outputFolder << "/" if !outputFolder.end_with? "/"

# Is project folder an Arduino project?
projectName = projectFolder.split("/").last

if Dir["#{File.expand_path("#{projectFolder}#{projectName}#{arduinoExtensions}")}"].length() == 0 then
  abort "Project folder doesn't look like an Arduino project folder"
end

# Empty outputFolder
FileUtils.rm_rf(Dir.glob("#{outputFolder}*"))

# Create wildcard
arduinoExtensionsWildcard = "#{projectFolder}#{arduinoExtensions}"
otherExtensionsToCopyWildcard = "#{projectFolder}#{otherExtensionsToCopy}"


# Unify .ino and .pde files
unifiedSource = ""
Dir["#{File.expand_path(arduinoExtensionsWildcard)}"].each.map do |file|
  unifiedSource << "\n// \"#{File.basename(file)}\"\n"
  unifiedSource << File.read(file)
end

# Write unifiedSource as .ino to outputFolder
unifiedSourcePath = "#{outputFolder}#{projectName}.ino"
File.open(unifiedSourcePath, "w") { |file| file.write(unifiedSource) }

# Copy ohter source files to outputFolder
Dir["#{File.expand_path(otherExtensionsToCopyWildcard)}"].each.map do |file|
  FileUtils.copy(file, "#{outputFolder}#{File.basename(file)}")
end


# Use ctags to create prototypes

# Exectute ctags
command = "#{Shellwords.escape(File.dirname(__FILE__))}/ctags #{ctagsArguments} #{Shellwords.escape(unifiedSourcePath)}".force_encoding('UTF-8')
ctagsOutput = %x[#{command}]

# Parse ctags output
tags = []

ctagsOutput.each_line do |row|

  next if row.empty?

  columns = row.split("\t")

  tag = {"functionName" => columns[0]}

  columns.each do |column|
    if column.include?(":")
      colonIndex = column.index(":")
      fieldName = column[0...colonIndex]
      if fields.include? fieldName
        tag[fieldName] = column[colonIndex+1..column.length()].chomp.strip
      end
    end

    if column.include?('/^') && column.include?('/;') then
      if column.include?('{') then
        tag["code"] = column[column.index("\^")+1...column.index("{")].chomp.strip
      else
        tag["code"] = column[column.index("\^")+1..column.rindex(")")].chomp.strip
      end
    end

  end
  tags << tag
end

# Filter out unknown tags
tags.delete_if do|tag|
  if !knownTagKinds.include? tag["kind"]
    true
  end
end

# Remove existing prototypes
existingPrototypes = tags.select {|tag| tag["kind"] == "prototype"}

tags.delete_if do |tag|
  delete = false
  existingPrototypes.each do |prototype|
    if prototype["functionName"] == tag["functionName"]
      delete = true
      break
    end
  end
  delete
end

# Add prototypes
tags.each do |tag|
  if tag["returntype"].start_with?("template") || tag["code"].start_with?("template") then
    tag["prototype"] = tag["code"]
  else
    prototype = tag["returntype"] << " " << tag["functionName"] << tag["signature"] << ";"
    tag["prototype"] = prototype
  end
end

# Remove default argument values
tags.each do |tag|
  if tag["prototype"].include? "="
    arguments = tag["prototype"][tag["prototype"].index("(")+1...tag["prototype"].index(")")]
    argumetsWithoutValues = arguments.split(",").each{|arg| arg[arg.index("=")..arg.length()] = "" if arg.index("=")}.map(&:rstrip).join(",")
    tag["prototype"][tag["prototype"].index("(")+1...tag["prototype"].index(")")] = argumetsWithoutValues
  end
end

# Sort prototypes
tags.sort! { |x,y| x["line"].to_i <=> y["line"].to_i }

# Create prototypes string
prototypes = ""
tags.each {|tag| prototypes << tag["prototype"] << "\n"}

# Where to insert prototypes – find first statement
text_patterns = '\s*#.*?$'      # Preprocessor directive
text_patterns << '|\/\/.*?$'    # Single line comment
text_patterns << '|\/\*[^*]*(?:\*(?!\/)[^*]*)*\*\/' # Multi line comment
text_patterns << '|\s+'         # Whitespace
text_pattern = Regexp.new(text_patterns)

prototypeInsertPos = 0
unifiedSource.gsub(text_pattern) do |match|
  break if !($~.begin(0) == prototypeInsertPos)
  prototypeInsertPos = $~.end(0)
end


# Insert the prototypes and write file
unifiedSource.insert(prototypeInsertPos, "\n" << prototypes << "\n")
File.open(unifiedSourcePath, "w") { |file| file.write(unifiedSource) }
