require 'ostruct'

module ArchiveUrlGenerators
  module InternetArchive
    module_function

    def run_check(latest_addeddate, logger)
      pf = PackFinder.new(latest_addeddate, 1000, logger)
      pe = PackExpander.new(pf, logger)
      ge = Generator.new(logger)

      failed_pack_urls = []
      ret = OpenStruct.new(archive_urls: [])

      pe.each do |pack_url, resp, ok, addeddate, urls|
        logger.info "Processing #{pack_url} (#{urls.length} URLs)"

        if ok
          archive_urls, errored = ge.archive_urls(urls)

          ret.archive_urls += archive_urls

          if errored
            logger.error "#{pack_url} did not completely process"
            failed_pack_urls << pack_url
          else
            logger.info "Successfully processed #{pack_url} (addeddate: #{addeddate})"
            ret.latest_addeddate = addeddate
          end
        else
          logger.error "Fetch #{pack_url} failed with response code #{resp.code}"
          failed_pack_urls << pack_url
        end
      end

      ret
    end
  end
end

require File.expand_path('../internet_archive/pack_finder', __FILE__)
require File.expand_path('../internet_archive/pack_expander', __FILE__)
require File.expand_path('../internet_archive/generator', __FILE__)
