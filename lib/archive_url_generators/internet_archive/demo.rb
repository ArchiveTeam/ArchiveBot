require 'json'
require 'logger'

require './pack_finder'
require './pack_expander'
require './generator'

logger = Logger.new($stderr)
logger.level = Logger::INFO

start_at = if File.exists?('lastpack')
             Time.parse(File.read('lastpack')).strftime('%Y-%m-%d')
           end

pf = ArchiveUrlGenerators::InternetArchive::PackFinder.new(start_at, 1000, logger)
pe = ArchiveUrlGenerators::InternetArchive::PackExpander.new(pf, logger)
ge = ArchiveUrlGenerators::InternetArchive::Generator.new(logger)

failed_pack_urls = []

pe.each do |pack_url, resp, ok, addeddate, urls|
  logger.info "#{pack_url}: #{urls.length}"

  if ok
    archive_urls, errored = ge.archive_urls(urls)

    if errored
      logger.error "#{pack_url} did not completely process"
      failed_pack_urls << pack_url
    else
      fn = "#{pack_url.gsub('/', '_')}-#{addeddate}.json"

      File.open(fn, 'w') do |f|
        f.write(archive_urls.to_json)
      end

      logger.info "Wrote #{archive_urls.length} archive URLs to #{fn}"

      File.open('lastpack', 'w') do |f|
        f.write(addeddate.to_s)
      end

      logger.info "Set last update date to #{addeddate}"
    end
  end
end
