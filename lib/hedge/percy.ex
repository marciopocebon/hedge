defmodule Hedge.Percy do
  require Logger

  @polling_freq 15_000 # ms

  def commit(sha) do
    Task.async fn ->
      # TODO: abandon the polling after a while
      poll(sha)

      Logger.debug "#{sha}: polling complete"
    end
  end

  defp poll(sha) do
    :timer.sleep @polling_freq

    {status, data} = Percy.poll(sha)

    case status do
      :ok  -> parse_response(sha, data)
      :err -> Logger.warn "#{sha}: error: #{data}"
    end
  end

  defp parse_response(sha, data) when is_nil(data) do
    Logger.debug "#{sha}: no builds yet"

    poll(sha)
  end

  defp parse_response(sha, data) do
    attrs = data["attributes"]
    state = attrs["state"]
    review_state = attrs["review-state"]
    build = attrs["build-number"]
    percy_url = attrs["web-url"]

    cond do
      state == "finished" && review_state == "approved" ->
        Logger.debug "#{sha}: build #{build} is approved"

        Github.update_status(
          sha,
          "success",
          "Percy build ##{build} has been approved",
          percy_url
        )
      state == "finished" || state == "pending" ->
        Logger.debug "#{sha}: build #{build} is #{review_state}"

        Github.update_status(
          sha,
          "pending",
          "Percy build ##{build} is pending approval",
          percy_url
        )

        poll(sha)
      true ->
        Logger.debug "#{sha}: build #{build} is in an unknown state"
        Logger.debug "#{sha}: state is #{state}, review state is #{review_state}"

        Github.update_status(
          sha,
          "error",
          "Percy (or this integration) encountered an error"
        )
    end
  end
end
