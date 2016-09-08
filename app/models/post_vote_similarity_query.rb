require 'aws-sdk'

class PostVoteSimilarityQuery
  attr_reader :user_id

  def initialize(user_id)
    @user_id = user_id
  end

  def results
    if redis.zcard(redis_key) == 0
      sqs_client.send_message(
        message_body: redis_key,
        queue_url: Rails.application.config.x.aws_sqs_similarity_queue_url
      )
      return "not ready"
    else
      redis.zrevrange(redis_key, 0, 12, with_scores: true)
    end
  end

  def results_text
    ret = results()
    if ret == "not ready"
      return ret
    else
      return ret.join(" ")
    end
  end

  def calculate
    return if redis.zcard(redis_key) > 0

    posts0 = PostVote.positive_post_ids(user_id)
    PostVote.unique_user_ids.each do |user_id|
      posts1 = PostVote.positive_post_ids(user_id)
      redis.zadd(redis_key, calculate_with_cosine(posts0, posts1), user_id)
    end
    redis.zremrangebyrank(redis_key, 0, -13)
    redis.expire(redis_key, 36.hours.to_i)
  end

private

  def sqs_client
    @sqs_client ||= begin
      Aws::SQS::Client.new
    end
  end
  
  def redis_key
    "simpvotes-#{user_id}"
  end

  def redis
    @redis ||= Redis.new
  end

  def calculate_with_cosine(posts0, posts1)
    a = (posts0 & posts1).size
    div = Math.sqrt(posts0.size * posts1.size)
    if div == 0
      0
    else
      a / div
    end
  end
end
