module Reports
  class Uploads < Base
    def calculate_data(user_id)
      user = DanbooruRo::User.find(user_id)
      name = user.name
      client = BigQuery::PostVersion.new
      tda = date_window.strftime("%F %H:%M")
      total = DanbooruRo::Post.where("created_at > ?", tda).where(uploader_id: user.id).count
      queue_bypass = DanbooruRo::Post.where("created_at > ?", tda).where(uploader_id: user.id, approver_id: nil, is_deleted: false, is_pending: false).count
      deleted = DanbooruRo::Post.where("created_at > ?", tda).where(uploader_id: user.id, is_deleted: true).count
      parent = DanbooruRo::Post.where("parent_id is not null and created_at > ?", tda).where(uploader_id: user.id).count
      source = DanbooruRo::Post.where("source <> '' and source is not null and created_at > ?", tda).where(uploader_id: user.id).count
      safe = DanbooruRo::Post.where("created_at > ?", tda).where(uploader_id: user.id, rating: "s").count
      questionable = DanbooruRo::Post.where("created_at > ?", tda).where(uploader_id: user.id, rating: "q").count
      explicit = DanbooruRo::Post.where("created_at > ?", tda).where(uploader_id: user.id, rating: "e").count
      general = client.count_general_added_v1(user_id, tda)
      character = client.count_character_added_v1(user_id, tda)
      copyright = client.count_copyright_added_v1(user_id, tda)
      artist = client.count_artist_added_v1(user_id, tda)

      return {
        id: user_id,
        name: name,
        total: total,
        queue_bypass: queue_bypass,
        deleted: deleted,
        parent: parent,
        source: source,
        safe: safe,
        questionable: questionable,
        explicit: explicit,
        general: general,
        character: character,
        copyright: copyright,
        artist: artist
      }
    end

    def generate
      htmlf = Tempfile.new("#{file_name}_html")
      jsonf = Tempfile.new("#{file_name}_json")

      begin
        data = []

        candidates.each do |user_id|
          data << calculate_data(user_id)
        end

        data = data.sort_by {|x| -x[:total].to_i}

        engine = Haml::Engine.new(html_template)
        htmlf.write(engine.render(Object.new, data: data))

        jsonf.write("[")
        jsonf.write(data.map {|x| x.to_json}.join(","))
        jsonf.write("]")

        htmlf.rewind
        jsonf.rewind

        upload(htmlf, "#{file_name}.html", "text/html")
        upload(jsonf, "#{file_name}.json", "application/json")
      ensure
        jsonf.close
        htmlf.close
      end
    end
  end
end
