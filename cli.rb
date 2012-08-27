#!/usr/bin/env ruby
$:.unshift File.dirname(__FILE__)
require 'tmpdir'
require 'abbyy'
require 'optparse'
require 'mixlib/shellout'

options = {}

rest = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename $0} [options] [inputfile]"
  opts.on('-o', '--output-filename [NAME]',
          "Basename of the output files. defaults to input filename of 'document.pdf'") do |f|
    options[:output_name] = filename
  end
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.order!

if rest.empty?
  options[:input] = STDIN.read
else
  options[:inputfile] = rest.first
  options[:output_name] ||= File.basename options[:inputfile]
end
options[:output_name]||='document.pdf'

#puts options.inspect

tmp_dir=File.join(ENV['HOME'],'ocr')

Dir.mktmpdir('ocr',tmp_dir) do |dir|
  #puts "Creating tempdir #{dir}"
  abbyy = Abbyy9.new dir
  output_dir, output_files = if options[:input]
    abbyy.process(options[:input], options[:output_name])
  else
    abbyy.process_file(options[:inputfile])
  end.first

  tar_command = "tar -c -z -f - -C #{output_dir} #{output_files.join(' ')}"
  #puts tar_command
  tar_cli = Mixlib::ShellOut.new(tar_command)
  tar_cli.live_stream=STDOUT
  tar_cli.run_command
  #tar_cli.error!
  #puts output_files.inspect
end
