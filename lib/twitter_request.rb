##
# Represents an archive request from Twitter.
class TwitterRequest < Struct.new(:url, :tweet_id, :user_id, :username)
end
