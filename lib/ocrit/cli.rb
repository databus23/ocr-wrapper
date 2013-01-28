require 'tmpdir'
require 'ocrit/abbyy'
require 'mixlib/shellout'
require 'logger'
require 'thor'
require 'yaml'

module OCRIt
  class Cli < Thor
    include Thor::Actions
    
    class <<self
      def bin!
        start 
      end
    end
     
    desc 'process', 'Receive input file via STDIN and return ocr result via stdout'
    method_option :logfile, :aliases => '-l'
    method_option :ocr_bin, :default => '/opt/ABBYYOCR9/abbyyocr9'
    method_option :languages, :type=> :array, :default => %w(German English)
    method_option :opts, :type => :array
    method_option :exports, :type => :array, :default => %w(f:PDFA pdfaPictureResolution:original pdfaQuality:85 pdfExportMode:ImageOnText of:{INPUT}.pdf)
    method_option :mock, :type => :boolean, :default => false 
    def process
      tmp_dir=File.join(ENV['HOME'],'ocr')
      FileUtils.mkdir_p tmp_dir unless File.exist? tmp_dir
      Dir.mktmpdir('ocr',tmp_dir) do |dir|
        logger.debug "Creating tempdir #{dir}"
        input_file = STDIN.read
        abbyy = Abbyy9.new(CoreExt::HashWithIndifferentAccess.new({work_dir: dir, input: input_file, logger: logger}.merge options))
        
        output_dir, output_files = abbyy.process
        tar = Mixlib::ShellOut.new("tar -c -z -f - -C #{output_dir} #{output_files.join(' ')}")
        tar.logger=logger
        tar.live_stream=STDOUT
        tar.run_command
        tar.error! 
      end
    rescue => e
      logger.error "An error occurred: #{e.message}"
      logger.error "Backtrace:\n#{e.backtrace.join("\n")}"
      exit 1
 
    end

    desc 'remote INPUT_FILE OUTPUT_DIR', 'Send input file via ssh to remote ocr server'
    method_option :config, :alias => '-c', :default => '~/.ocrit'
    method_option :user, :alias => '-u'
    method_option :host, :alias => '-h'
    method_option :output_name, :alias => '-o'
    def remote(input_file, output_dir)
      config = config_from_file options[:config]
      user = options[:user] || config['user'] || ENV['USER']
      host = options[:host] || config['host']
      output_name = options[:output_name] || File.basename(input_file).gsub(/\.[^.]+$/,'')

      cmd = 'ocrit process'
      cmd << ' --mock' if ENV['MOCK']
      cmd << " --languages=#{config['languages'].join(' ')}" if config['languages']
      %w{opts exports}.each do |key|
        next unless config[key]
        cmd << " --#{key}=" << config[key].collect_concat{|v| v.collect {|k,v| v ? "#{k}:#{v}" : k} }.compact.join(' ')
      end
      cmd.gsub!(/%INPUT%/, output_name) 
      ssh = Mixlib::ShellOut.new("ssh #{user}@#{host} #{cmd} < #{input_file}", timeout: 600, logger:logger)
      #shell.live_stream = STDOUT
      ssh.run_command
      ssh.error!
      puts ssh.stderr if ssh.stderr
      tar = Mixlib::ShellOut.new("tar -zx -C #{output_dir}", logger:logger)
      tar.input = ssh.stdout
      tar.run_command
      tar.error!
    end

    private
    def config_from_file file
      config_file = File.expand_path file
      YAML::load(IO.read config_file) if File.exist? config_file
    end
    def logger
      @logger ||= begin
        l = Logger.new(STDERR)
        hostname = `hostname`.gsub(/(\..*)?\s*$/,'')[0,8].ljust(8,' ')
        l.formatter = proc do |severity, datetime, progname, msg|
          "#{datetime.strftime('%b %d %H:%M:%S')} #{hostname} #{msg}\n"
        end
        l
      end 
    end
  end
end
