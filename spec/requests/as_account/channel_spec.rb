# encoding: UTF-8
require 'spec_helper'
require 'yt/models/channel'

describe Yt::Channel, :device_app do
  subject(:channel) { Yt::Channel.new id: id, auth: $account }

  context 'given someone else’s channel' do
    let(:id) { 'UCxO1tY8h1AhOz0T4ENwmpow' }

    it 'returns valid metadata' do
      expect(channel.title).to be_a String
      expect(channel.description).to be_a String
      expect(channel.thumbnail_url).to be_a String
      expect(channel.published_at).to be_a Time
      expect(channel.privacy_status).to be_a String
      expect(channel.view_count).to be_an Integer
      expect(channel.comment_count).to be_an Integer
      expect(channel.video_count).to be_an Integer
      expect(channel.subscriber_count).to be_an Integer
      expect(channel.subscriber_count_visible?).to be_in [true, false]
    end

    describe '.videos' do
      let(:video) { channel.videos.first }

      specify 'returns the videos in the channel without tags or category ID' do
        expect(video).to be_a Yt::Video
        expect(video.snippet).not_to be_complete
      end

      describe '.where(id: *anything*)' do
        let(:video) { channel.videos.where(id: 'invalid').first }

        specify 'is ignored (all the channel’s videos are returned)' do
          expect(video).to be_a Yt::Video
        end
      end

      describe '.where(chart: *anything*)' do
        let(:video) { channel.videos.where(chart: 'invalid').first }

        specify 'is ignored (all the channel’s videos are returned)' do
          expect(video).to be_a Yt::Video
        end
      end

      describe '.includes(:statistics, :status)' do
        let(:video) { channel.videos.includes(:statistics, :status).first }

        specify 'eager-loads the statistics and status of each video' do
          expect(video.instance_variable_defined? :@statistics_set).to be true
          expect(video.instance_variable_defined? :@status).to be true
        end
      end

      describe '.includes(:content_details)' do
        let(:video) { channel.videos.includes(:content_details).first }

        specify 'eager-loads the statistics of each video' do
          expect(video.instance_variable_defined? :@content_detail).to be true
        end
      end

      describe '.includes(:category)' do
        let(:video) { channel.videos.includes(:category, :status).first }

        specify 'eager-loads the category (id and title) of each video' do
          expect(video.instance_variable_defined? :@snippet).to be true
          expect(video.instance_variable_defined? :@video_category).to be true
        end
      end

      describe 'when the channel has more than 500 videos' do
        let(:id) { 'UC0v-tlzsn0QZwJnkiaUSJVQ' }

        specify 'the estimated and actual number of videos can be retrieved' do
          # @note: in principle, the following three counters should match, but
          #   in reality +video_count+ and +size+ are only approximations.
          expect(channel.video_count).to be > 500
          expect(channel.videos.size).to be > 500
        end

        specify 'over 500 videos can only be retrieved when sorting by date' do
          # @note: these tests are slow because they go through multiple pages
          # of results to test that we can overcome YouTube’s limitation of only
          # returning the first 500 results when ordered by date.
          expect(channel.videos.count).to be > 500
          expect(channel.videos.where(order: 'viewCount').count).to be 500
        end

        specify 'over 500 videos can be retrieved even with a publishedBefore condition' do
          # @note: these tests are slow because they go through multiple pages
          # of results to test that we can overcome YouTube’s limitation of only
          # returning the first 500 results when ordered by date.
          today = Date.today.beginning_of_day.iso8601(0)
          expect(channel.videos.where(published_before: today).count).to be > 500
        end
      end
    end

    describe '.playlists' do
      describe '.includes(:content_details)' do
        let(:playlist) { channel.playlists.includes(:content_details).first }

        specify 'eager-loads the content details of each playlist' do
          expect(playlist.instance_variable_defined? :@content_detail).to be true
        end
      end
    end

    it { expect(channel.playlists.first).to be_a Yt::Playlist }
    it { expect{channel.delete_playlists}.to raise_error Yt::Errors::RequestError }

    describe '.related_playlists' do
      let(:related_playlists) { channel.related_playlists }

      specify 'returns the list of associated playlist (Liked Videos, Uploads, ...)' do
        expect(related_playlists.first).to be_a Yt::Playlist
      end

      specify 'includes public related playlists (such as Liked Videos)' do
        uploads = related_playlists.select{|p| p.title.starts_with? 'Uploads'}
        expect(uploads).not_to be_empty
      end

      specify 'does not includes private playlists (such as Watch Later)' do
        watch_later = related_playlists.select{|p| p.title.starts_with? 'Watch'}
        expect(watch_later).to be_empty
      end
    end

    specify 'with a public list of subscriptions' do
      expect(channel.subscribed_channels.first).to be_a Yt::Channel
    end

    context 'with a hidden list of subscriptions' do
      let(:id) { 'UCG0hw7n_v0sr8MXgb6oel6w' }
      it { expect{channel.subscribed_channels.size}.to raise_error Yt::Errors::Forbidden }
    end

    # NOTE: These tests are slow because we *must* wait some seconds between
    # subscribing and unsubscribing to a channel, otherwise YouTube will show
    # wrong (cached) data, such as a user is subscribed when he is not.
    context 'that I am not subscribed to', :slow do
      let(:id) { 'UCCj956IF62FbT7Gouszaj9w' }
      before { channel.throttle_subscriptions }

      it { expect(channel.subscribed?).to be false }
      it { expect(channel.unsubscribe).to be_falsey }
      it { expect{channel.unsubscribe!}.to raise_error Yt::Errors::RequestError }

      context 'when I subscribe' do
        before { channel.subscribe }
        after { channel.unsubscribe }

        it { expect(channel.subscribed?).to be true }
        it { expect(channel.unsubscribe!).to be_truthy }
      end
    end

    context 'that I am subscribed to', :slow do
      let(:id) { 'UCxO1tY8h1AhOz0T4ENwmpow' }
      before { channel.throttle_subscriptions }

      it { expect(channel.subscribed?).to be true }
      it { expect(channel.subscribe).to be_falsey }
      it { expect{channel.subscribe!}.to raise_error Yt::Errors::RequestError }

      context 'when I unsubscribe' do
        before { channel.unsubscribe }
        after { channel.subscribe }

        it { expect(channel.subscribed?).to be false }
        it { expect(channel.subscribe!).to be_truthy }
      end
    end
  end

  context 'given my own channel' do
    let(:id) { $account.channel.id }
    let(:title) { 'Yt Test <title>' }
    let(:description) { 'Yt Test <description>' }
    let(:tags) { ['Yt Test Tag 1', 'Yt Test <Tag> 2'] }
    let(:privacy_status) { 'unlisted' }
    let(:params) { {title: title, description: description, tags: tags, privacy_status: privacy_status} }

    specify 'subscriptions can be listed (hidden or public)' do
      expect(channel.subscriptions.size).to be
    end

    describe 'playlists can be deleted' do
      let(:title) { "Yt Test Delete All Playlists #{rand}" }
      before { $account.create_playlist params }

      it { expect(channel.delete_playlists title: %r{#{params[:title]}}).to eq [true] }
      it { expect(channel.delete_playlists params).to eq [true] }
      it { expect{channel.delete_playlists params}.to change{channel.playlists.count}.by(-1) }
    end

    # Can't subscribe to your own channel.
    it { expect{channel.subscribe!}.to raise_error Yt::Errors::RequestError }
    it { expect(channel.subscribe).to be_falsey }

    it 'returns valid reports for channel-related metrics' do
      # Some reports are only available to Content Owners.
      # See content owner test for more details about what the methods return.
      expect{channel.views}.not_to raise_error
      expect{channel.comments}.not_to raise_error
      expect{channel.likes}.not_to raise_error
      expect{channel.dislikes}.not_to raise_error
      expect{channel.shares}.not_to raise_error
      expect{channel.subscribers_gained}.not_to raise_error
      expect{channel.subscribers_lost}.not_to raise_error
      expect{channel.favorites_added}.not_to raise_error
      expect{channel.favorites_removed}.not_to raise_error
      expect{channel.videos_added_to_playlists}.not_to raise_error
      expect{channel.videos_removed_from_playlists}.not_to raise_error
      expect{channel.estimated_minutes_watched}.not_to raise_error
      expect{channel.average_view_duration}.not_to raise_error
      expect{channel.average_view_percentage}.not_to raise_error
      expect{channel.annotation_clicks}.not_to raise_error
      expect{channel.annotation_click_through_rate}.not_to raise_error
      expect{channel.annotation_close_rate}.not_to raise_error
      expect{channel.viewer_percentage}.not_to raise_error
      expect{channel.earnings}.to raise_error Yt::Errors::Unauthorized
      expect{channel.impressions}.to raise_error Yt::Errors::Unauthorized
      expect{channel.monetized_playbacks}.to raise_error Yt::Errors::Unauthorized
      expect{channel.playback_based_cpm}.to raise_error Yt::Errors::Unauthorized

      expect{channel.views_on 3.days.ago}.not_to raise_error
      expect{channel.comments_on 3.days.ago}.not_to raise_error
      expect{channel.likes_on 3.days.ago}.not_to raise_error
      expect{channel.dislikes_on 3.days.ago}.not_to raise_error
      expect{channel.shares_on 3.days.ago}.not_to raise_error
      expect{channel.subscribers_gained_on 3.days.ago}.not_to raise_error
      expect{channel.subscribers_lost_on 3.days.ago}.not_to raise_error
      expect{channel.favorites_added_on 3.days.ago}.not_to raise_error
      expect{channel.favorites_removed_on 3.days.ago}.not_to raise_error
      expect{channel.videos_added_to_playlists_on 3.days.ago}.not_to raise_error
      expect{channel.videos_removed_from_playlists_on 3.days.ago}.not_to raise_error
      expect{channel.estimated_minutes_watched_on 3.days.ago}.not_to raise_error
      expect{channel.average_view_duration_on 3.days.ago}.not_to raise_error
      expect{channel.average_view_percentage_on 3.days.ago}.not_to raise_error
      expect{channel.earnings_on 3.days.ago}.to raise_error Yt::Errors::Unauthorized
      expect{channel.impressions_on 3.days.ago}.to raise_error Yt::Errors::Unauthorized
    end

    it 'cannot give information about its content owner' do
      expect{channel.content_owner}.to raise_error Yt::Errors::Forbidden
      expect{channel.linked_at}.to raise_error Yt::Errors::Forbidden
    end
  end

  context 'given an unknown channel' do
    let(:id) { 'not-a-channel-id' }

    it { expect{channel.snippet}.to raise_error Yt::Errors::NoItems }
    it { expect{channel.status}.to raise_error Yt::Errors::NoItems }
    it { expect{channel.statistics_set}.to raise_error Yt::Errors::NoItems }
    it { expect{channel.subscribe}.to raise_error Yt::Errors::RequestError }

    describe 'starting with UC' do
      let(:id) { 'UC-not-a-channel-id' }

      # NOTE: This test is just a reflection of YouTube irrational behavior of
      # returns 0 results if the name of an unknown channel starts with UC, but
      # returning 100,000 results otherwise (ignoring the channel filter).
      it { expect(channel.videos.count).to be_zero }
      it { expect(channel.videos.size).to be_zero }
    end
  end
end
