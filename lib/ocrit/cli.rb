require 'tmpdir'
require 'ocrit/abbyy'
require 'ocrit/sequence'
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
      def exit_on_failure?; true; end
    end
    class_option :logfile, :aliases => '-l', :default => 'STDOUT'

    def initialize(*)
      super
    end
     
    desc 'process', 'Receive input file via STDIN and return ocr result via stdout'
    method_option :ocr_bin, :default => '/opt/ABBYYOCR9/abbyyocr9'
    method_option :languages, :type=> :array, :default => %w(German English)
    method_option :opts, :type => :array
    method_option :exports, :type => :array, :default => %w(f:PDFA pdfaPictureResolution:original pdfaQuality:85 pdfExportMode:ImageOnText of:{INPUT}.pdf)
    method_option :mock, :type => :boolean, :default => false 
    def process
      #make sure we log to stderr, because stdout is the transport channel for the result
      @logfile = STDERR
      tmp_dir=File.join(ENV['HOME'],'ocr')
      FileUtils.mkdir_p tmp_dir unless File.exist? tmp_dir
      Dir.mktmpdir('ocr',tmp_dir) do |dir|
        logger.debug "Created tempdir #{dir}"
        Dir.chdir(dir) do |dir|
          input_file = STDIN.read
          abbyy = Abbyy9.new(CoreExt::HashWithIndifferentAccess.new({work_dir: dir, input: input_file, logger: logger}.merge options))
          output_dir, output_files = abbyy.process
          tar = Mixlib::ShellOut.new("tar -c -z -f - -C #{output_dir} #{output_files.join(' ')}")
          tar.logger=logger
          tar.live_stream=STDOUT
          tar.run_command
          tar.error!
        end 
      end
    rescue => e
      logger.error "An error occurred: #{e.message}"
      logger.error "Backtrace:\n#{e.backtrace.join("\n")}"
      exit 1
 
    end

    desc 'remote INPUT_FILE OUTPUT_DIR', 'Send input file via ssh to remote ocr server'
    method_option :user, :aliases => '-u'
    method_option :host, :aliases => '-h'
    method_option :output_name, :aliases => '-o', :default => '{INPUT}'
    method_option :remote_command, :aliases => '-r'
    method_option :config, :aliases => '-c', :default => '~/.ocrit'
    def remote(input_file, output_dir)
      config = config_from_file options[:config]
      user = options[:user] || config['user'] || ENV['USER']
      host = options[:host] || config['host']
      output_name = expand_name options[:output_name]
      remote_command = options['remote_command'] || config['remote_command'] || 'ocrit'
      cmd = "#{remote_command} process"
      cmd << ' --mock' if ENV['MOCK']
      cmd << " --languages=#{config['languages'].join(' ')}" if config['languages']
      %w{opts exports}.each do |key|
        next unless config[key]
        cmd << " --#{key}=" << config[key].collect_concat{|v| v.collect {|k,v| v ? "#{k}:#{v}" : k} }.compact.join(' ')
      end
      cmd.gsub!(/{NAME}/, output_name) 
      ssh = Mixlib::ShellOut.new("ssh #{user}@#{host} #{cmd} < #{input_file}", timeout: 600, logger:logger)
      #shell.live_stream = STDOUT
      ssh.run_command
      ssh.error!
      logger<< ssh.stderr if ssh.stderr
      tar = Mixlib::ShellOut.new("tar -zx -C #{output_dir}", logger:logger)
      tar.input = ssh.stdout
      tar.run_command
      tar.error!
    rescue => e
      log_error e, "ocrit remote"
      exit 1
    end

    desc 'pages LICENSE', 'Show Abbyy page counter'
    method_option :config, :aliases => '-c', :default => '~/.ocrit'
    def pages(license = nil)
      config = config_from_file(options[:config])
      user = options[:user] || config['user'] || ENV['USER']
      host = options[:host] || config['host']
      license ||= config['license']

      ssh = Mixlib::ShellOut.new("ssh #{user}@#{host} abbyyocr9LV #{license}", timeout: 600, logger:logger)
      ssh.run_command
      ssh.error!
      puts "Pages per year : " + ssh.stdout[/(\d+) pages per year available to process/,1]
      puts "Pages left     : " + ssh.stdout[/Current: (\d+) pages?/,1]
    end

    desc 'directory INPUT_DIR OUTPUT_DIR', 'Process all files in a directory'
    method_option :input_filter, :default => '*.pdf'
    method_option :name, :default => '%Y%m%d-{ID#5}'
    method_option :output_filter, :default => '{NAME}.pdf'
    method_option :archive_dir
    method_option :archive_original, :type => :boolean, :default => true
    def directory(input_dir, output_dir)
      archive_dir = options[:archive_dir]
      FileUtils.mkdir_p if archive_dir && !File.exists?(archive_dir)
      #config = config_from_file options[:config]
      Dir.glob(File.join input_dir, options[:input_filter]).each do |input|
        next if File.exists?(input + '.error.log')
        begin
          logger.info "-----------------------------------------------------"
          logger.info "Processing file #{input}"
          output_name = expand_name options[:name]
          Dir.mktmpdir('ocr') do |dir|
            ocrit = Mixlib::ShellOut.new("#{$0} remote -l STDOUT --output_name #{output_name} #{input} #{dir}", timeout: 600, logger:logger)
            ocrit.run_command
            logger<< ocrit.stdout
            ocrit.error!
            Dir.glob(File.join dir, '*').each do |file|
              if file =~ Regexp.new(options[:output_filter].gsub(/{NAME}/,output_name))
                logger.info "Moving #{File.basename file} to #{output_dir}"
                FileUtils.mv file, output_dir
              else
                if archive_dir
                  logger.info "Archieving #{File.basename file} to #{archive_dir}"
                  FileUtils.mv file, archive_dir
                else
                  logger.info "Discarding #{file}"
                end
              end
            end
            if archive_dir
              dest = File.join archive_dir, "#{output_name}_original#{suffix input}" 
              logger.info "Archieving input file #{File.basename input} to #{dest}"
              FileUtils.mv input, dest
            else
              logger.info "Deleting input file #{File.basename input}"
              FileUtils.safe_unlink input
            end
          end
          logger.info "Completed processing #{input}"
          logger.info "-----------------------------------------------------"
        rescue => e
          logger.error "Failed to process #{input}"
          File.open(input + '.error.log', 'w') do |f|
             f.write(e.message)
          end
          next
        end 
      end
    rescue => e
      log_error e, "ocrit directory"
      exit 1
    end

    private
    def suffix filename
      filename[/(\.[^.]+)$/,1]
    end
    def strip_suffix filename
      filename.gsub(/\.[^.]+$/,'')
    end
    def expand_name(filename)
      #Substitute 
      name = Time.now.strftime filename
      name = name.gsub '{INPUT}', strip_suffix(File.basename filename)
      name.gsub /{ID(#(\d+))?}/ do
        ($2 ? "%0#{$2}d": "%d") % Sequence.new.next
      end
    end 
    
    def config_from_file file
      config_file = File.expand_path file
      YAML::load(IO.read config_file) if File.exist? config_file
    end
    def logger
      @logfile ||= case options[:logfile]
                     when /stdout/i then STDOUT
                     when /stderr/i then STDERR
                     when NilClass then '/dev/null'
                     else options[:logfile]
                   end 
      @logger ||= begin
        l = Logger.new @logfile
        hostname = `hostname`.gsub(/(\..*)?\s*$/,'')[0,8].ljust(8,' ')
        l.formatter = proc do |severity, datetime, progname, msg|
          "#{datetime.strftime('%b %d %H:%M:%S')} #{hostname} #{msg}\n"
        end
        l
      end 
    end

    def log_error(e, msg=nil)
      logger.error "An error occured while #{msg}:"
      logger.error e.message
      logger<< "Backtrace: \n" + e.backtrace.join("\n") + "\n"
    end
  end
end
