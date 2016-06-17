#!/home/danbooru/.rbenv/shims/ruby

require "redis"
require "logger"
require 'optparse'
require "json"
require "big_query"
require File.expand_path("../../../config/environment", __FILE__)

Process.daemon
Process.setpriority(Process::PRIO_USER, 0, 10)

$running = true
$options = {
  pidfile: "/var/run/reportbooru/post_version_exporter.pid",
  logfile: "/var/log/reportbooru/post_version_exporter.log",
  google_key_path: "/var/www/reportbooru/shared/google-key.json",
  google_data_set: "danbooru_#{Rails.env}"
}

OptionParser.new do |opts|
  opts.on("--pidfile=PIDFILE") do |pidfile|
    $options[:pidfile] = pidfile
  end

  opts.on("--logfile=LOGFILE") do |logfile|
    $options[:logfile] = logfile
  end

  opts.on("--google_key=KEYFILE") do |keyfile|
    $options[:google_key_path] = keyfile
  end
end.parse!

google_config = JSON.parse(File.read($options[:google_key_path]))

logfile = File.open($options[:logfile], "a")
logfile.sync = true
LOGGER = Logger.new(logfile)
REDIS = Redis.new
BATCH_SIZE = 10_000
GBQ = BigQuery::Client.new(
  "json_key" => $options[:google_key_path],
  "project_id" => google_config["project_id"],
  "dataset" => $options[:google_data_set]
)

File.open($options[:pidfile], "w") do |f|
  f.write(Process.pid)
end

Signal.trap("TERM") do
  $running = false
end

def get_last_exported_id
  REDIS.get("post-version-exporter-id").to_i
end

def find_previous(version)
  if version.updated_at.to_i == Time.zone.parse("2007-03-14T19:38:12Z").to_i
    # Old post versions which didn't have updated_at set correctly
    PostVersion.where("post_id = ? and updated_at = ? and id < ?", version.post_id, version.updated_at, version.id).order("updated_at desc, id desc").first
  else
    PostVersion.where("post_id = ? and updated_at < ?", version.post_id, version.updated_at).order("updated_at desc, id desc").first
  end
end

def calculate_diff(older, newer)
  if older
    older_tags = older.tags.scan(/\S+/)
    older_tags << "rating:#{older.rating}" if older.rating.present?
    older_tags << "parent:#{older.parent_id}" if older.parent_id.present?
    older_tags << "source:#{older.source}" if older.source.present?
  else
    older_tags = []
  end

  newer_tags = newer.tags.scan(/\S+/)
  newer_tags << "rating:#{newer.rating}" if newer.rating.present?
  newer_tags << "parent:#{newer.parent_id}" if newer.parent_id.present?
  newer_tags << "source:#{newer.source}" if newer.source.present?

  added_tags = newer_tags - older_tags
  removed_tags = older_tags - newer_tags

  return {
    :added_tags => added_tags,
    :removed_tags => removed_tags
  }
end

while $running
  begin
    last_id = get_last_exported_id
    next_id = last_id + BATCH_SIZE
    store_id = last_id
    batch = []
    PostVersion.where("id > ? and id <= ?", last_id, next_id).find_each do |version|
      previous = find_previous(version)
      diff = calculate_diff(previous, version)
      hash = {
        "id" => version.id,
        "updated_at" => version.updated_at,
        "post_id" => version.post_id,
        "tags" => version.tags,
        "added_tags" => diff[:added_tags].join(" "),
        "removed_tags" => diff[:removed_tags].join(" "),
        "rating" => version.rating,
        "parent_id" => version.parent_id,
        "source" => version.source,
        "updater_id" => version.updater_id,
        "updater_ip_addr" => version.updater_ip_addr.to_s
      }
      batch << hash
      if version.id > store_id
        store_id = version.id
      end
    end

    if batch.any?
      LOGGER.info "inserting #{last_id}..#{store_id}"
      result = GBQ.insert("post_versions", batch)
      if result["insertErrors"]
        LOGGER.error result.inspect
        sleep(180)
      else
        REDIS.set("post-version-exporter-id", store_id)
      end
    else
      sleep(60)
    end

  rescue Exception => e
    LOGGER.error "error: #{e}"
    sleep(60)
    retry
  end
end