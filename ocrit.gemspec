Gem::Specification.new do |s|
  s.name        = 'ocrit'
  s.version     = '0.0.2'
  s.summary     = "OCR wrapper around finereader cli for linux!"
  s.description = "A simple hello world gem"
  s.authors     = ["databus23"]
  s.email       = 'databus23@gmail.com'
  s.homepage    = 'https://github.com/databus23/ocr-wrapper'
  s.has_rdoc    = false
  s.files       = Dir['lib/ocrit/*.rb']
  s.bindir     = 'bin'
  s.executables = %w{ocrit}
  s.add_dependency('mixlib-shellout')
  s.add_dependency('thor')
end
