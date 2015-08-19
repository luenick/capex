# config valid only for current version of Capistrano
lock '3.3.5'

set :application, 'anything'
set :repo_url, 'git@github.com:luenick/anything.git'
set :branch, 'deploy'

# Default branch is :master
# ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }.call

# Default deploy_to directory is /var/www/my_app_name
set :deploy_to, '/home/deploy/platform'

# Default value for :scm is :git
# set :scm, :git

# Default value for :format is :pretty
# set :format, :pretty

# Default value for :log_level is :debug
# set :log_level, :debug

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
set :linked_files, fetch(:linked_files, []).push('config/database.yml', 'config/secrets.yml', 'config/application.yml')

# Default value for linked_dirs is []
set :linked_dirs, fetch(:linked_dirs, []).push('log', 'tmp/pids', 'tmp/cache', 'tmp/sockets', 'vendor/bundle', 'public/system')

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for keep_releases is 5
# set :keep_releases, 5

namespace :deploy do
  namespace :assets do

    desc 'Run the precompile task locally and upload to server'
    task :precompile_locally_archive do
      on roles(:app) do
        run_locally do
          if RUBY_PLATFORM =~ /(win32)|(i386-mingw32)/
            execute 'del "tmp/assets.tar.gz"' rescue nil

            # precompile
            with rails_env: fetch(:rails_env) do
              execute 'rake assets:precompile'
            end
            #execute "RAILS_ENV=#{rails_env} rake assets:precompile"

            # use 7zip to archive
            execute '7z a -ttar assets.tar public/assets/'
            execute '7z a -tgzip assets.tar.gz assets.tar'
            execute 'del assets.tar'
            execute 'move assets.tar.gz tmp/'
          else
            execute 'rm tmp/assets.tar.gz' rescue nil

            with rails_env: fetch(:rails_env) do
              execute 'rake assets:precompile'
            end

            execute 'touch assets.tar.gz && rm assets.tar.gz'
            execute 'tar zcvf assets.tar.gz public/assets/'
            execute 'mv assets.tar.gz tmp/'
          end
        end

        # Upload precompiled assets
        execute 'rm -rf public/assets/*'
        upload! "tmp/assets.tar.gz", "#{release_path}/assets.tar.gz"
        execute "cd #{release_path} && tar zxvf assets.tar.gz && rm assets.tar.gz"
      end
    end

  end
end

namespace :deploy do

  after :restart, :clear_cache do
    on roles(:web), in: :groups, limit: 3, wait: 10 do
      # Here we can do anything such as:
      # within release_path do
      #   execute :rake, 'cache:clear'
      # end
    end
  end

end

namespace :deploy do

  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      execute :touch, release_path.join('tmp/restart.txt')
    end
  end

  after :publishing, 'deploy:assets:precompile_locally_archive', 'deploy:restart'
  after :finishing, 'deploy:cleanup'
end

# cap [stage] rails:console or cap [stage] rails:dbconsole
namespace :rails do
  desc "Remote console"
  task :console do
    on roles(:app) do |h|
      run_interactively "bundle exec rails console #{fetch(:rails_env)}", h.user
    end
  end

  desc "Remote dbconsole"
  task :dbconsole do
    on roles(:app) do |h|
      run_interactively "bundle exec rails dbconsole #{fetch(:rails_env)}", h.user
    end
  end

  def run_interactively(command, user)
    info "Running `#{command}` as #{user}@#{host}"
    exec %Q(ssh #{user}@#{host} -t "bash --login -c 'cd #{fetch(:deploy_to)}/current && #{command}'")
  end
end
