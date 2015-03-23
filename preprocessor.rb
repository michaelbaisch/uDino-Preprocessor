#!/usr/bin/env ruby
# encoding: utf-8

require 'fileutils'
require 'shellwords'

# µDino preprocessor
# Inspired from https://github.com/ffissore/Arduino/blob/coanctags/arduino-core/src/processing/app/preproc/CTagsParser.java


ctagsArguments = "--language-force=c++ -f - --c++-kinds=pf --fields=KSTtzn"   # Original: --c++-kinds=svpf
fields = ['kind', 'line', 'typeref', 'signature', 'returntype']
knownTagKinds = ["prototype", "function"]
arduinoExtensions = "{*.ino,*.pde}"
otherExtensionsToCopy = "{*.cpp,*.c,*.h,*.S}"
allExtensions = arduinoExtensions[0..-2] << "," << otherExtensionsToCopy[1..-1]


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


# Create wildcards
arduinoExtensionsWildcard = "#{projectFolder}#{arduinoExtensions}"
otherExtensionsToCopyWildcard = "#{projectFolder}#{otherExtensionsToCopy}"
allExtensionsOutputFolderWildcard = "#{outputFolder}#{allExtensions}"

# Empty outputFolder
Dir["#{File.expand_path(allExtensionsOutputFolderWildcard)}"].each {|file| File.delete(file) }

# Gather all .ino and .pde files
allFiles = Dir["#{File.expand_path(arduinoExtensionsWildcard)}"].each.map {|file| file }

# Sort files
  # Main project file should be first
  # Sort alphabetically
allFiles.sort! do |x,y|
  #File.basename(x, ".*") == projectName ? -1 : File.basename(y, ".*") == projectName ? 1 : File.basename(x) <=> File.basename(y)
  if File.basename(x, ".*") == projectName then -1
  elsif File.basename(y, ".*") == projectName then 1
  else File.basename(x) <=> File.basename(y) end
end

# Unify .ino and .pde files
unifiedSource = ""
allFiles.each do |file|
  unifiedSource << "#line 1 \"#{File.basename(file)}\"\n"
  unifiedSource << File.read(file)
  unifiedSource << "\n" if !unifiedSource.end_with?("\n")
end

# Write unifiedSource as .ino to outputFolder
unifiedSourcePath = "#{outputFolder}#{projectName}.ino"
File.open(unifiedSourcePath, "w") {|file| file.write(unifiedSource) }

# Copy other source files to outputFolder
Dir["#{File.expand_path(otherExtensionsToCopyWildcard)}"].each do |file|
  FileUtils.copy(file, "#{outputFolder}#{File.basename(file)}")
end


# Use ctags to create prototypes

# Exectute ctags
command = "#{Shellwords.escape(File.dirname(__FILE__))}/bin/ctags #{ctagsArguments} #{Shellwords.escape(unifiedSourcePath)}".force_encoding('UTF-8')
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
      if fields.include? fieldName then
        tag[fieldName] = column[colonIndex+1..column.length()].chomp.strip
      end
    end

    if column.include?('/^') && column.include?('/;') then
      if column.include?('{') then
        tag["code"] = column[column.index("\^")+1...column.index("{")].chomp.strip
      elsif column.include?(')') then
        tag["code"] = column[column.index("\^")+1..column.rindex(")")].chomp.strip
      end
    end

  end
  tags << tag
end

# Filter out unknown tags
tags.delete_if {|tag| !knownTagKinds.include?(tag["kind"]) }

# Remove existing prototypes
existingPrototypes = tags.select {|tag| tag["kind"] == "prototype" }

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
  if ((!tag["returntype"].nil? && tag["returntype"].start_with?("template")) || (!tag["code"].nil? && tag["code"].start_with?("template"))) && !tag["code"].nil? then
    tag["prototype"] = tag["code"]
  elsif (!tag["returntype"].nil? && !tag["functionName"].nil? && !tag["signature"].nil?)
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
tags.sort! {|x,y| x["line"].to_i <=> y["line"].to_i }

# Create prototypes string
prototypes = ""
tags.each {|tag| prototypes << tag["prototype"] << "\n" }

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

prototypeInsertLineNubmerOffset = unifiedSource[0...prototypeInsertPos].scan(/#line\s/).count
prototypeInsertLineNubmer = unifiedSource[0...prototypeInsertPos].lines.count - prototypeInsertLineNubmerOffset + 1   # start at line 1

# Insert the prototypes and write file
unifiedSource.insert(prototypeInsertPos, prototypes << "#line #{prototypeInsertLineNubmer}" << "\n")
File.open(unifiedSourcePath, "w") {|file| file.write(unifiedSource) }
