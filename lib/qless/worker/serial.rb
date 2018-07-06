# Encoding: utf-8

# Qless requires
require 'qless'
require 'qless/worker/base'
require 'qless/job_reservers/ordered'

module Qless
  module Workers
    # A worker that keeps popping off jobs and processing them
    class SerialWorker < BaseWorker
      def self.create_for_queues(queues, client, options)
        queues = queues.to_s.split(',').map { |q| client.queues[q.strip] }
        if queues.none?
          raise "No queues provided. You must pass queues when starting a worker."
        end
        reserver = JobReservers::Ordered.new(queues)
        new(reserver, options)
      end

      def initialize(reserver, options = {})
        super(reserver, options)
      end

      def run
        log(:info, "Starting #{reserver.description} in #{Process.pid}")
        procline "Starting #{reserver.description}"
        register_signal_handlers

        reserver.prep_for_work!

        listen_for_lost_lock do
          procline "Running #{reserver.description}"

          jobs.each do |job|
            # Run the job we're working on
            log(:debug, "Starting job #{job.klass_name} (#{job.jid} from #{job.queue_name})")
            procline "Processing: #{job.jid} (#{job.klass_name}) from #{job.queue_name}"
            perform(job)
            log(:debug, "Finished job #{job.klass_name} (#{job.jid} from #{job.queue_name})")

            # So long as we're paused, we should wait
            while paused
              log(:debug, 'Paused...')
              sleep interval
            end
          end
        end
      rescue NoMethodError => e
        raise NoMethodError, e.message + " BACKTRACE: #{e.backtrace.join("; ")}"
      end
    end
  end
end
