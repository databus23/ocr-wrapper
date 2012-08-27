require 'mixlib/shellout'
require 'logger'
class Abbyy9
  attr_accessor :logger
  def initialize work_dir, bin_path='/opt/ABBYYOCR9//abbyyocr9'
    @bin_path=bin_path
    FileUtils.mkdir_p work_dir, :mode => 0700 unless File.exist? work_dir
    @work_dir = work_dir
    self.logger=Logger.new('/dev/null')
  end

  def process document, filename="document.pdf"
    input_file = File.join(@work_dir,filename)
    File.open(input_file,'w') {|f|f.puts document}
    process_file input_file
  end

  def process_file filename, output_formats = [{:pdfa => {:mode=>:ImageOnText}}, {:pdfa => {:mode => :TextOnly, :suffix=>'_text'}}, {:xml=>{}}]
    #strip basename
    basename = File.basename(filename).gsub(/\.[^.]+$/,'')
    output_dir = File.join(@work_dir,'output')
    FileUtils.mkdir_p output_dir, :mode => 0700 unless File.exist? output_dir
    output_files=[]
    #open image and analysis options
    command= "#{@bin_path} --recognitionLanguage German English --tempFileFolder #{@work_dir}"
    #input file
    command << " -if #{filename}"

    output_formats.each do |f|
      type, options = f.first
      case type
        when :pdfa
          command << " -f PDFA"
          command << " --pdfaPictureResolution original"
          command << " --pdfaQuality #{options[:quality] || 85}"
          command << " --pdfaExportMode #{options[:mode]}" if options[:mode]
        when :pdf
          command << " -f PDF"
          command << " --pdfPictureResolution original"
          command << " --pdfQuality #{options[:quality] || 85}"
          command << " --pdfExportMode #{options[:mode]}" if options[:mode]
        when :xml
          command << " -f XML"
      end
      output_file = "#{basename}#{options[:suffix]}.#{type.eql?(:pdfa) ? 'pdf' : type}"
      command << " -of #{File.join(output_dir,output_file)}"
      output_files << output_file
    end
    logger.info command
    ocr_command = Mixlib::ShellOut.new("command")
    ocr_command.logger=logger
    ocr_command.run_command
    #abby_cli.error!
    return output_dir => output_files
  end

end
