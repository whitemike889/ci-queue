module CI
  module Queue
    module Redis
      class Base
        def initialize(redis:, build_id:)
          @redis = redis
          @build_id = build_id
        end

        def empty?
          size == 0
        end

        def size
          redis.multi do
            redis.llen(key('queue'))
            redis.zcard(key('running'))
          end.inject(:+)
        end

        def to_a
          redis.multi do
            redis.lrange(key('queue'), 0, -1)
            redis.zrange(key('running'), 0, -1)
          end.flatten.reverse
        end

        def progress
          total - size
        end

        def wait_for_master(timeout: 10)
          return true if master?
          (timeout * 10 + 1).to_i.times do
            case master_status
            when 'ready', 'finished'
              return true
            else
              sleep 0.1
            end
          end
          raise LostMaster, "The master worker is still `#{master_status}` after 10 seconds waiting."
        end

        def workers_count
          redis.scard(key('workers'))
        end

        private

        attr_reader :redis, :build_id

        def key(*args)
          ['build', build_id, *args].join(':')
        end

        def master_status
          redis.get(key('master-status'))
        end

        def eval_script(script, *args)
          redis.evalsha(load_script(script), *args)
        end

        def load_script(script)
          @scripts_cache ||= {}
          @scripts_cache[script] ||= redis.script(:load, read_script(script))
        end

        def read_script(name)
          ::File.read(::File.join(DEV_SCRIPTS_ROOT, "#{name}.lua"))
        rescue SystemCallError
          ::File.read(::File.join(RELEASE_SCRIPTS_ROOT, "#{name}.lua"))
        end
      end
    end
  end
end