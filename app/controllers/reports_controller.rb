class ReportsController < ApplicationController
  rescue_from ActionController::ParameterMissing, with: :render_422
  rescue_from UploadReport::ReportError, with: :render_error
  rescue_from UploadReport::VerificationError, with: :render_403
  layout false
  before_filter :check_shared_key, only: :user_similarity

  def uploads
    response.headers["X-Frame-Options"] = "ALLOWALL"

    params.require(:tags)

    @report = UploadReport.new(params[:min], params[:max], params[:tags], params[:sig])
  end

  def user_similarity
    query = UserSimilarityQuery.new(params[:user_id])
    render text: query.results_text
  end

  def post_vote_similarity
    query = PostVoteSimilarityQuery.new(params[:user_id])
    render text: query.results_text
  end

private

  def render_error(e)
    render text: e.to_s, status: 422
  end

  def render_422
    render text: "Tags missing"
  end

  def render_403
    render nothing: true, status: 403
  end

end
