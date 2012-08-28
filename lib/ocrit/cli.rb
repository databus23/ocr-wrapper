
require 'tmpdir'
require 'ocrit/abbyy'
require 'optparse'
require 'mixlib/shellout'
require 'logger'
module OCRIt
  class Cli
    def initialize
      @logger = Logger.new(STDERR)
      @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
    end
    def run
      options = {}

      rest = OptionParser.new do |opts|
        opts.banner = "Usage: #{File.basename $0} [options] [inputfile]"
        opts.on('-o', '--output-filename [NAME]',
                "Basename of the output files. defaults to input filename of 'document.pdf'") do |f|
          options[:output_name] = f
        end
        opts.on('-l', "--log-file [FILE]",
                      "log to file. default: STDERR") do |l|
          options[:logfile]=l
          @logger=Logger.new(options[:logfile])
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


      tmp_dir=File.join(ENV['HOME'],'ocr')
      FileUtils.mkdir_p tmp_dir unless File.exist? tmp_dir

      Dir.mktmpdir('ocr',tmp_dir) do |dir|
        @logger.debug "Creating tempdir #{dir}"
        abbyy = Abbyy9.new dir
        abbyy.logger=@logger
        output_dir, output_files = if options[:input]
          abbyy.process(options[:input], options[:output_name])
        else
          abbyy.process_file(options[:inputfile])
        end.first

        tar_command = "tar -c -z -f - -C #{output_dir} #{output_files.join(' ')}"
        tar_cli = Mixlib::ShellOut.new(tar_command)
        tar_cli.logger=@logger
        tar_cli.live_stream=STDOUT
        tar_cli.run_command
      end
    rescue => e
      @logger.error "An error occurred: #{e.message}"
      @logger.error "Backtrace:\n#{e.backtrace.join("\n")}"
      exit 1
    end
  end
end