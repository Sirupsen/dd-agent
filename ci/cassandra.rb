require './ci/common'

# TODO: make this available in the matrix
def cass_version
  ENV['FLAVOR_VERSION'] || '2.1.3'
end

def cass_rootdir
  "#{ENV['INTEGRATIONS_DIR']}/cass_#{cass_version}"
end

namespace :ci do
  namespace :cassandra do |flavor|
    task :before_install => ['ci:common:before_install']

    task :install => ['ci:common:install'] do
      unless Dir.exist? File.expand_path(cass_rootdir)
        # Downloads
        # http://cassandra.apache.org/download/
        sh %(curl -s -L\
             -o $VOLATILE_DIR/apache-cassandra-#{cass_version}-bin.tar.gz\
              https://s3.amazonaws.com/dd-agent-tarball-mirror/apache-cassandra-#{cass_version}-bin.tar.gz)
        sh %(mkdir -p #{cass_rootdir})
        sh %(tar zxf $VOLATILE_DIR/apache-cassandra-#{cass_version}-bin.tar.gz\
             -C #{cass_rootdir} --strip-components=1)
      end
    end

    task :before_script => ['ci:common:before_script'] do
      sh %(cp $TRAVIS_BUILD_DIR/ci/resources/cassandra/cassandra_#{cass_version.split('.')[0..1].join('.')}.yaml #{cass_rootdir}/conf/cassandra.yaml)
      sh %(#{cass_rootdir}/bin/cassandra -p $VOLATILE_DIR/cass.pid)
      # Create temp cassandra workdir
      sh %(mkdir -p $VOLATILE_DIR/cassandra)
      # Wait for cassandra to init
      sleep_for 10
    end

    task :script => ['ci:common:script'] do
      this_provides = [
        'cassandra'
      ]
      Rake::Task['ci:common:run_tests'].invoke(this_provides)
    end

    task :before_cache => :cleanup

    task :cache => ['ci:common:cache']

    task cleanup: ['ci:common:cleanup'] do
      sh %(kill `cat $VOLATILE_DIR/cass.pid`)
      sleep_for 3
      sh %(rm -rf #{cass_rootdir}/data)
    end

    task :execute do
      exception = nil
      begin
        %w(before_install install before_script script).each do |t|
          Rake::Task["#{flavor.scope.path}:#{t}"].invoke
        end
      rescue => e
        exception = e
        puts "Failed task: #{e.class} #{e.message}".red
      end
      if ENV['SKIP_CLEANUP']
        puts 'Skipping cleanup, disposable environments are great'.yellow
      else
        puts 'Cleaning up'
        Rake::Task["#{flavor.scope.path}:cleanup"].invoke
      end
      if ENV['TRAVIS'] && ENV['AWS_SECRET_ACCESS_KEY']
        %w(before_cache cache).each do |t|
          Rake::Task["#{flavor.scope.path}:#{t}"].invoke
        end
      end
      fail exception if exception
    end
  end
end
