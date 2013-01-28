require 'mixlib/shellout'
require 'logger'
module OCRIt
  class Abbyy9
    attr_accessor :logger
    attr_reader :ocr_bin, :work_dir, :opts, :input_file
    def initialize opts
      @mock       = !!opts[:mock]
      @ocr_bin    = opts[:ocr_bin] || '/opt/ABBYYOCR9/abbyyocr9'
      @work_dir   = opts[:work_dir] || '/tmp'
      @output_dir  = opts[:output_dir] || File.join(work_dir, 'output')
      [@work_dir, @output_dir].each do |d|
        FileUtils.mkdir_p d, :mode => 0700 unless File.exist? d
      end
      @languages  = opts[:languages]
      @opts       = opts[:opts] || []
      @exports    = opts[:exports]

      if opts[:input_file]
        @input_file = opts[:input_file] 
      elsif opts[:input]
        @input_file = File.join(work_dir, 'input.pdf')
        File.open(@input_file,'w') {|f|f.puts opts[:input]} unless @mock
      else
        raise "option input or input_file missing"
      end
      self.logger = opts[:logger] || Logger.new('/dev/null')
    end
    def build_command
      cmd = ocr_bin
      cmd << " --tempFileFolder #{work_dir}"
      cmd << " --recognitionLanguage #{@languages.join(' ')}" if @languages
      @opts.each do |o|
        cmd << " #{to_arg o}"
      end
      cmd << " -if #{input_file}"
      @exports.each do |e|
        cmd << " #{to_arg e}"
      end
      cmd      
    end
    def to_arg string
      key, arg = string.split(':')
      result = if key =~ /a-z{1,4}/
                 "-#{key}"
               else
                 "--#{key}"
               end
      arg = case key
        when /^(of|outputFileName)$/
          @output_files||=[]
          @output_files << arg
          File.join(@output_dir, arg)
        else
        arg
      end
      result << " #{arg}" if arg
      result
    end

    def process
      ocr_command = Mixlib::ShellOut.new(build_command, timeout:600, logger:logger)
      if @mock
        logger.info "Mocking: #{ocr_command.command}"
        @output_files.each do |f|
          FileUtils.touch File.join(@output_dir, f)
        end
      else 
        ocr_command.run_command
        ocr_command.error!
      end
      return @output_dir, @output_files
    end

  end
end
