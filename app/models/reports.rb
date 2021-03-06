module Reports
  def generate_all
    [AddRequestTags, Approvers, ArtistCommentaries, Artists, BulkUpdateRequests, Comments, ContributorUploads, ForumPosts, ForumTopics, InactiveApprovers, MemberUploads, Pools, PostAppeals, PostChanges, PostFlags, PostReplacements, Notes, SuperVoters, TagAliases, TagImplications, Taggers, TagVandalism, TranslatorTags, WikiPages].each do |model|
      model.new.generate
    end
  end

  module_function :generate_all
end
