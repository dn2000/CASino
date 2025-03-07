class CASino::SessionsController < CASino::ApplicationController
  include CASino::SessionsHelper
  include CASino::AuthenticationProcessor
  include CASino::TwoFactorAuthenticatorProcessor

  before_action :validate_login_ticket, only: [:create]
  before_action :validate_user_exist, only: [:create]
  before_action :ensure_service_allowed, only: [:new, :create]
  before_action :load_ticket_granting_ticket_from_parameter, only: [:validate_otp]
  before_action :ensure_signed_in, only: [:index, :destroy]

  def index
    @ticket_granting_tickets = current_user.ticket_granting_tickets.active
    @two_factor_authenticators = current_user.two_factor_authenticators.active
    @login_attempts = current_user.login_attempts.order(created_at: :desc).first(5)
  end

  def new
    tgt = current_ticket_granting_ticket
    return handle_signed_in(tgt) unless params[:renew] || tgt.nil?
    redirect_to(params[:service]) if params[:gateway] && params[:service].present?
  end

  def create
    #validation_result = validate_login_credentials(params[:username], params[:password])
    if !@validation_result
      log_failed_login params[:username]
      show_login_error I18n.t('login_credential_acceptor.invalid_login_credentials')
    else
      sign_in(validation_result, long_term: params[:rememberMe], credentials_supplied: true)
    end
  end

  def destroy
    tickets = current_user.ticket_granting_tickets.where(id: params[:id])
    tickets.first.destroy if tickets.any?
    redirect_to sessions_path
  end

  def destroy_others
    current_user
      .ticket_granting_tickets
      .where('id != ?', current_ticket_granting_ticket.id)
      .destroy_all if signed_in?
    redirect_to params[:service] || sessions_path
  end

  def logout
    sign_out
    @url = params[:url]
    if params[:service].present? && service_allowed?(params[:service])
      redirect_to params[:service], status: :see_other
    end
  end

  def validate_otp
    validation_result = validate_one_time_password(params[:otp], @ticket_granting_ticket.user.active_two_factor_authenticator)
    return flash.now[:error] = I18n.t('validate_otp.invalid_otp') unless validation_result.success?
    @ticket_granting_ticket.update_attribute(:awaiting_two_factor_authentication, false)
    set_tgt_cookie(@ticket_granting_ticket)
    handle_signed_in(@ticket_granting_ticket)
  end

  private

  def show_login_error(message)
    flash.now[:error] = message
    render :new, status: :forbidden
  end

  def validate_login_ticket
    unless CASino::LoginTicket.consume(params[:lt])
      show_login_error I18n.t('login_credential_acceptor.invalid_login_ticket')
    end
  end

  def validate_user_exist
    @validation_result = validate_login_credentials(params[:username], params[:password])
    if !@validation_result
      require 'oauth2'
#      client = OAuth2::Client.new('63cc4d99c35957b9accca21c719cc22eb9789f6069fa371617d3676c9dc325e4', '770364babf68a71e72a9ad4026cdac57b13badb805afac02841a78cee1396db4', site: ENV['SH4'], :raise_errors => false)
      client = OAuth2::Client.new('63cc4d99c35957b9accca21c719cc22eb9789f6069fa371617d3676c9dc325e4', '770364babf68a71e72a9ad4026cdac57b13badb805afac02841a78cee1396db4', site: 'http://779c8da2b34a.ngrok.io')

      #token = client.auth_code.get_token(code.code, redirect_uri: 'http://localhost:3000/oauth2/callback', headers: {'Authorization' => 'Basic some_password'})
      #token = client.client_credentials.get_token
      token = client.password.get_token(params[:username], params[:password])
      puts token
      #response = token.get('/api/v1/people', :headers => { 'Accept' => 'application/json' }, :params => { page: 1 })
      require 'json'
#      response = JSON.parse(token.get('/api/v1/users/get_data', :headers => { 'Accept' => 'application/json' }, params: {'email' => params[:username], 'password' => params[:password]}))
#      response = JSON.parse(token.get('/api/v1/me', :headers => { 'Accept' => 'application/json' }))
      response = token.get('/api/v1/me', :headers => { 'Accept' => 'application/json' })
      #hash = JSON.parse(response.body)
      puts response

      if !response
        #ans = User:create(email: params[:username], password: params[:password])

        #puts ans.to_json

        #User.create!(params[:user])
        @validation_result = validate_login_credentials(params[:username], params[:password])
      end
    end
  end

  def ensure_service_allowed
    if params[:service].present? && !service_allowed?(params[:service])
      render 'service_not_allowed', status: :forbidden
    end
  end

  def load_ticket_granting_ticket_from_parameter
    @ticket_granting_ticket = find_valid_ticket_granting_ticket(params[:tgt], request.user_agent, ignore_two_factor: true)
    redirect_to login_path if @ticket_granting_ticket.nil?
  end
end
