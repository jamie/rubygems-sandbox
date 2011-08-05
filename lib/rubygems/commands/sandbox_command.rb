# -*- coding: utf-8 -*-
require 'rubygems/command'
require 'rubygems/dependency_installer'

##
# Gem command to "sandbox" command-line tools into their own private
# gem repos but with a globally command-line wrapper.

class Gem::DependencyInstaller
  attr_accessor :bin_dir
end

class Gem::Commands::SandboxCommand < Gem::Command
  VERSION = '1.0.0'

  def initialize
    defaults = Gem::DependencyInstaller::DEFAULT_OPTIONS.merge(
      :generate_rdoc     => false,
      :generate_ri       => false,
      :format_executable => false,
      :version           => Gem::Requirement.default
    )

    super("sandbox", "Privately install a command-line tool", defaults)

    @scripts = []
  end


  def arguments # :nodoc:
    ['SUBCOMMAND    one of: install, update, plugin, remove, help',
     'GEMNAME       name of a gem to sandbox'].join "\n"
  end

  def usage # :nodoc:
    "#{program_name} SUBCOMMAND GEMNAME(S)"
  end

  def description
    <<-EOF

`gem sandbox` helps you manage your command-line tools and their
dependencies. Sandboxed gems are installed in their own private
repositories with their dependencies. This means that you don't have
to have a rats nest of gems in your global repository in order to run
popular command-tools like rdoc, flog, flay, rcov, etc.

`gem sandbox` has the following sub-commands:

  * install   gem_name ...             - install 1 or more gems
  * plugin    gem_name plugin_name ... - install a gem and plugins for it
  * list                               - list sandboxed gems
  * uninstall gem_name ...             - uninstall 1 or more gems
  * help                               - show this output

Once you install `gem sandbox` will output something like:

    Copy the following scripts to any directory in your path to use them:

    cp /Users/USER/.gem/sandboxes/TOOL/bin/TOOL _in_your_$PATH_

Copy the scripts to a directory in your path (eg ~/bin or /usr/bin)
and you're good to go.
    EOF
  end

  def execute
    cmd = options[:args].shift

    case cmd
    when "install" then
      install
    when "plugin" then
      plugin
    when "uninstall" then
      abort "not implemented yet"
    when "list" then
      list
    when "help", "usage" then
      show_help
      abort
    else
      alert_error "Unknown sandbox subcommand: #{cmd}"
      show_help
      abort
    end
  end

  def install
    get_all_gem_names.each do |gem_name|
      install_gem gem_name
    end

    list_scripts
  end

  def plugin
    gem_name, *plugins = options[:args]
    dir                = sandbox_dir gem_name

    install_gem gem_name, dir

    plugins.each do |plugin_name|
      inst = Gem::DependencyInstaller.new options.merge(:install_dir => dir)
      inst.install plugin_name, options[:version]
    end

    list_scripts
  end

  def list_scripts
    say ""
    say "Copy the following scripts to any directory in your path to use them:"
    say ""
    say "cp #{@scripts.join ' '} _in_your_$PATH_"
  end

  def sandbox_dir gem_name
    File.join Gem.user_home, '.gem', "sandboxes", gem_name
  end

  def list
    say ""
    say "Sandboxed gems:"
    Dir[sandbox_dir('*')].each do |path|
      # This is totally a giant hack, but I don't know gem internals well
      # enough to look it up properly
      gem = File.split(path).last
      gemdir = Dir[File.join path, 'gems', "#{gem}-*"].first
      version = gemdir.match(/([\d.]+)$/)[1]
      # TODO: gem list includes "ruby" after the version, probably useful info
      say "#{gem} (#{version})"
    end
  end

  def install_gem gem_name, dir = sandbox_dir(gem_name)
    # Forces reset of known installed gems so subsequent repeats work
    Gem.use_paths nil, nil

    inst = Gem::DependencyInstaller.new options.merge(:install_dir => dir)
    inst.install gem_name, options[:version]

    spec = inst.installed_gems.find { |s| s.name == gem_name }
    rewrite_executables dir, spec

    say "Successfully installed #{gem_name}"
  end

  def rewrite_executables dir, spec
    spec.executables.each do |filename|
      path = File.join dir, "bin", filename
      env  = "ENV['GEM_HOME'] = ENV['GEM_PATH'] = #{dir.inspect}"

      script = File.read path
      script.sub!(/require 'rubygems'/, "#{env}\n\\&")

      File.open path, "w" do |f|
        f.write script
      end

      @scripts << path
    end
  end
end
