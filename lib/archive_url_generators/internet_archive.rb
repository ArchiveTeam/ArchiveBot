module ArchiveUrlGenerators
  module InternetArchive
    module_function

    def run_check(latest_addeddate, logger, recorder)
      pf = PackFinder.new(latest_addeddate, 1000, logger)
      pe = PackExpander.new(pf, logger)
      ge = Generator.new(logger)

      pe.each do |pack_url, resp, ok, addeddate, urls|
        logger.info "Processing #{pack_url} (#{urls.length} URLs)"

        if ok
          archive_urls, errored = ge.archive_urls(urls)
          ok = recorder.record_archive_urls(archive_urls)
          errored ||= !ok

          if errored
            logger.error "#{pack_url} did not completely process"
            recorder.record_failed_pack_url(pack_url)
          else
            logger.info "Successfully processed #{pack_url} (addeddate: #{addeddate})"
            recorder.set_latest_addeddate(addeddate)
          end
        else
          logger.error "Fetch #{pack_url} failed with response code #{resp.code}"
          recorder.record_failed_pack_url(pack_url)
        end
      end
    end
  end
end

require File.expand_path('../internet_archive/pack_finder', __FILE__)
require File.expand_path('../internet_archive/pack_expander', __FILE__)
require File.expand_path('../internet_archive/generator', __FILE__)
