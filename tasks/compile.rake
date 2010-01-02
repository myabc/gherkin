require File.dirname(__FILE__) + '/ragel_task'
require 'gherkin/i18n'

CLEAN.include [
  'pkg', 'tmp',
  '**/*.{o,bundle,jar,so,obj,pdb,lib,def,exp,log}', 'ext',
  'java/target',
  'ragel/i18n/*.rl',
  'lib/gherkin/rb_lexer/*.rb',
  'ext/**/*.c',
  'java/src/gherkin/lexer/*.java'
]

begin
  require 'rake/extensiontask'
  require 'rake/javaextensiontask'
rescue LoadError
  warn 'WARNING: Rake::JavaExtensionTask not installed. Will skip C and Java compilation.'
  task :compile # no-op
end

java_task = Rake::JavaExtensionTask.new('gherkin') do |ext|
  ext.ext_dir = 'java/src'
  ext.debug   = true
end if defined?(Rake::JavaExtensionTask)

Gherkin::I18n.all.each do |i18n|
  rb   = RagelTask.new('rb',   i18n)
  c    = RagelTask.new('c',    i18n) if defined?(Rake::ExtensionTask) && !defined?(JRUBY_VERSION)
  java = RagelTask.new('java', i18n) if defined?(Rake::JavaExtensionTask)

  if defined?(Rake::ExtensionTask) && !defined?(JRUBY_VERSION)
    extconf = "ext/gherkin_lexer_#{i18n.sanitized_key}/extconf.rb"
    file extconf do
      FileUtils.mkdir(File.dirname(extconf)) unless File.directory?(File.dirname(extconf))
      File.open(extconf, "w") do |io|
        io.write(<<-EOF)
require 'mkmf'
$CFLAGS << ' -O0 -Wall -Werror'
dir_config("gherkin_lexer_#{i18n.sanitized_key}")
have_library("c", "main")
create_makefile("gherkin_lexer_#{i18n.sanitized_key}")
EOF
      end
    end

    Rake::ExtensionTask.new("gherkin_lexer_#{i18n.sanitized_key}") do |ext|
      if ENV['RUBY_CC_VERSION']
        ext.cross_compile = true
        ext.cross_platform = 'i386-mingw32'
      end
    end

    # The way tasks are defined with compile:xxx (but without namespace) in rake-compiler forces us
    # to use these hacks for setting up dependencies. Ugly!
    Rake::Task["compile:gherkin_lexer_#{i18n.sanitized_key}"].prerequisites.unshift(extconf)
    Rake::Task["compile:gherkin_lexer_#{i18n.sanitized_key}"].prerequisites.unshift(c.target)
    Rake::Task["compile:gherkin_lexer_#{i18n.sanitized_key}"].prerequisites.unshift(rb.target)

    Rake::Task["compile"].prerequisites.unshift(extconf)
    Rake::Task["compile"].prerequisites.unshift(c.target)
    Rake::Task["compile"].prerequisites.unshift(rb.target)
  end

  if defined?(Rake::JavaExtensionTask)
    Rake::Task['compile:java'].prerequisites.unshift(java.target)
    Rake::Task['compile:java'].prerequisites.unshift(rb.target)
    # Another hack: Rake-Compiler internal source_files is memoized and set too
    # early, thus we have to force append Ragel-generated .java files.
    java_task.instance_variable_get(:@source_files) << java.target
  end
end
