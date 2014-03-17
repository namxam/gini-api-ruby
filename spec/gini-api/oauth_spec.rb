require 'spec_helper'

describe Gini::Api::OAuth do

  let(:user)          { 'user@gini.net' }
  let(:pass)          { 'secret' }
  let(:auth_code)     { '1234567890' }
  let(:state)         { '1234567890' }
  let(:code)          { 'abcdefghij'}
  let(:redirect)      { 'http://localhost' }
  let(:status)        { 303 }
  let(:token_status)  { 200 }
  let(:token_body)    { 'client_id=cid&client_secret=sec&code=1234567890&grant_type=authorization_code&redirect_uri=http%3A%2F%2Flocalhost' }
  let(:header)        { { 'location' => "https://api.gini.net?code=#{code}&state=#{state}" } }
  let(:oauth_site)    { 'https://user.gini.net' }
  let(:authorize_uri) { "#{oauth_site}/authorize?client_id=cid&redirect_uri=#{redirect}&response_type=code&state=#{state}" }
  let(:api) do
    double('API',
      client_id: 'cid',
      client_secret: 'sec',
      oauth_site: oauth_site,
      oauth_redirect: redirect
    )
  end

  describe '#new' do

    context 'login with username/password' do

      before do
        allow(SecureRandom).to \
          receive(:hex) { state }

        stub_request(:post,
          authorize_uri
        ).to_return(
          status: status,
          headers: header,
          body: {}
        )

        stub_request(:post,
          "#{oauth_site}/token"
        ).to_return(
          status: token_status,
          headers: {
            'content-type' => 'application/json'
          },
          body: {
            access_token: '123-456',
            token_type: 'bearer',
            expires_in: 300,
            refresh_token: '987-654'
          }.to_json
        )
      end

      subject(:oauth) do
        Gini::Api::OAuth.new(api,
          username: user,
          password: pass
        )
      end

      it { should respond_to(:destroy) }

      it 'does set token' do
        expect(oauth.token.token).to eql('123-456')
      end

      context 'with invalid credentials' do

        let(:status) { 500 }

        it do
          expect {
            Gini::Api::OAuth.new(
              api,
              username: user,
              password: pass
            ) }.to raise_error(Gini::Api::OAuthError, /Failed to acquire auth_code/)
        end

      end

      context 'with non-redirect status code' do

        let(:status) { 200 }

        it do
          expect {
            Gini::Api::OAuth.new(
              api,
              username: user,
              password: pass
            ) }.to raise_error(Gini::Api::OAuthError, /API login failed/)
        end
      end

      context 'with invalid location header' do

        let(:header) { { location: 'https://api.gini.net' } }

        it do
          expect {
            Gini::Api::OAuth.new(
              api,
              username: user,
              password: pass
            ) }.to raise_error(Gini::Api::OAuthError, /Failed to parse location header/)
        end

      end

      context 'with CSRF token mismatch' do

        let(:header) { { location: "https://rspec.gini.net?code=#{code}&state=hacked"} }

        it do
          expect {
            Gini::Api::OAuth.new(
              api,
              username: user,
              password: pass
            ) }.to raise_error(Gini::Api::OAuthError, /CSRF token mismatch detected/)
        end

      end

      context 'without code' do

        let(:header) { { location: "https://api.gini.net?state=#{state}"} }

        it do
          expect {
            Gini::Api::OAuth.new(
              api,
              username: user,
              password: pass
            ) }.to raise_error(Gini::Api::OAuthError, /Failed to extract code from location/)
        end

      end

      context 'with invalid client credentials' do

        let(:token_status) { 401 }

        it do
          expect {
            Gini::Api::OAuth.new(
              api,
              username: user,
              password: pass
            ) }.to raise_error(Gini::Api::OAuthError, /Failed to exchange auth_code/)
        end

      end

    end

    context 'login with auth_code' do

      before do
        stub_request(:post,
          "#{oauth_site}/token"
        ).with(
          body: 'client_id=cid&client_secret=sec&code=1234567890&grant_type=authorization_code&redirect_uri=http%3A%2F%2Flocalhost'
        ).to_return(
          status: token_status,
          headers: {
            'content-type' => 'application/json'
          },
          body: {
            access_token: '123-456',
            token_type: 'bearer',
            expires_in: 300,
            refresh_token: '987-654'
          }.to_json
        )
      end

      subject(:oauth) { Gini::Api::OAuth.new(api, auth_code: auth_code) }

      it 'does set token' do
        expect(oauth.token.token).to eql('123-456')
      end

      context 'overrides #refresh!' do

        it do
          expect(oauth.token).to respond_to(:refresh!)
        end

      end

      context 'overrides #request' do

        it do
          expect(oauth.token).to respond_to(:request)
        end

      end

    end

  end

  describe '#destroy' do

    let(:status) { 204 }
    let(:refresh_token) { false }

    before do
      stub_request(:post,
        "#{oauth_site}/token"
      ).with(
        body: 'client_id=cid&client_secret=sec&code=1234567890&grant_type=authorization_code&redirect_uri=http%3A%2F%2Flocalhost'
      ).to_return(
        status: token_status,
        headers: {
          'content-type' => 'application/json'
        },
        body: {
          access_token: '123-456',
          token_type: 'bearer',
          expires_in: 300,
          refresh_token: '987-654'
        }.to_json
      )

      stub_request(
        :delete,
        %r{/accessToken/123-456}
      ).to_return(status: status)

      oauth.token.stub(:refresh_token).and_return(refresh_token)
    end

    subject(:oauth) { Gini::Api::OAuth.new(api, auth_code: auth_code) }

    context 'with refresh token' do

      let(:refresh_token) { true }

      it 'does a refresh first' do
        expect(oauth.token).to receive(:refresh_token)
        expect(oauth.token).to receive(:refresh!)
        expect(oauth.destroy).to be_nil
      end

    end

    context 'without refresh token' do

      it 'destroys token directly' do
        expect(oauth.token).to receive(:refresh_token)
        expect(oauth.token).not_to receive(:refresh!)
        expect(oauth.destroy).to be_nil
      end
    end

    context 'with invalid token' do

      let(:status) { 404 }

      it do
        expect{oauth.destroy}.to raise_error Gini::Api::OAuthError, /Failed to destroy token/
      end
    end

    context 'with unexpected http status code' do

      let(:status) { 200 }

      it do
        expect{oauth.destroy}.to raise_error Gini::Api::OAuthError, /Failed to destroy token/
      end
    end
  end

  describe 'overridden AccessToken#refresh!' do

    before do
      stub_request(:post,
        "#{oauth_site}/token"
      ).with(
        body: 'client_id=cid&client_secret=sec&code=1234567890&grant_type=authorization_code&redirect_uri=http%3A%2F%2Flocalhost'
      ).to_return(
        status: token_status,
        headers: {
          'content-type' => 'application/json'
        },
        body: {
          access_token: '123-456',
          token_type: 'bearer',
          expires_in: 300,
          refresh_token: '987-654'
        }.to_json
      )
    end

    subject(:oauth) { Gini::Api::OAuth.new(api, auth_code: auth_code) }


    it do
      expect(oauth.token.token).to eql('123-456')

      stub_request(
        :post,
        "#{oauth_site}/token"
      ).to_return(
        status: 200,
        headers: {
          'content-type' => 'application/json'
        },
        body: {
          access_token: '42-42-42',
          token_type: 'bearer',
          expires_in: 300,
          refresh_token: '987-654'
        }.to_json
      )

      oauth.token.refresh!
      expect(oauth.token.token).to eql('42-42-42')
    end

  end

  describe 'overridden AccessToken#request' do

    before do
      stub_request(:post,
        "#{oauth_site}/token"
      ).with(
        body: 'client_id=cid&client_secret=sec&code=1234567890&grant_type=authorization_code&redirect_uri=http%3A%2F%2Flocalhost'
      ).to_return(
        status: token_status,
        headers: {
          'content-type' => 'application/json'
        },
        body: {
          access_token: '123-456',
          token_type: 'bearer',
          expires_in: 300,
          refresh_token: '987-654'
        }.to_json
      )
    end

    subject(:oauth) { Gini::Api::OAuth.new(api, auth_code: auth_code) }


    context 'with expired token' do

      it 'does call refresh!' do
        stub_request(:get, "https://user.gini.net/a")
        stub_request(
          :post,
          "#{oauth_site}/token"
        ).to_return(
          status: 200,
          headers: {
            'content-type' => 'application/json'
          },
          body: {
            access_token: '42-42-42',
            token_type: 'bearer',
            expires_in: -10,
            refresh_token: '987-654'
          }.to_json
        )

        expect(oauth.token).to receive(:refresh!)
        oauth.token.request(:get, '/a')
      end

    end

    context 'with valid token' do

      it 'does not call refresh!' do

        stub_request(:get, "https://user.gini.net/a")
        stub_request(
          :post,
          "#{oauth_site}/token"
        ).to_return(
          status: 200,
          headers: {
            'content-type' => 'application/json'
          },
          body: {
            access_token: '42-42-42',
            token_type: 'bearer',
            expires_in: 300,
            refresh_token: '987-654'
          }.to_json
        )

        expect(oauth.token).not_to receive(:refresh!)
        oauth.token.request(:get, '/a')
      end

    end

  end

end
