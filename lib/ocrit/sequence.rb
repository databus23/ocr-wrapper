require 'sqlite3'
require 'fileutils'
require 'sqlite3'
module OCRIt
  class Sequence
    @@location = File.expand_path '~/.sequence'
    
    def initialize(name = 'default')
      @name=name
      ensure_location
      @db = SQLite3::Database.new(File.join @@location, "#{@name}.sqlite3")
      ensure_schema
    end
    def next
      result=nil
      @db.transaction do |db|
        db.execute 'UPDATE document_seq SET nr=nr+1'
        result = db.get_first_value 'select nr from document_seq'
      end
      result
    end
    def current
      @db.get_first_value 'select nr from document_seq' 
    end
    private
    def ensure_location
      FileUtils.mkdir_p @@location unless File.exists? @@location
      raise "Sequence location %s is not writable" % [@@location] unless File.writable?(@@location) 
    end
    def ensure_schema
      if @db.execute('SELECT * FROM sqlite_master WHERE type=? AND name=?', 'table', 'document_seq').empty?
        @db.execute_batch <<-EOS
          CREATE TABLE document_seq(
            nr INTEGER NOT NULL DEFAULT 0
          );
          INSERT INTO document_seq DEFAULT VALUES;
      EOS
      end
    end
    
  end
end
