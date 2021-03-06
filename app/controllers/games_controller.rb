class GamesController < ApplicationController

  def new
    @game = Game.new
  end

  def create_or_join
    if current_user.nil?
      flash[:notice] = 'Please sign in to create or join a game'
      redirect_to :back
    elsif params[:commit] == 'Create'
      create
    elsif params[:commit] == 'Join'
      join
    else
      # SHOULD NEVER REACH HERE
    end
  end

  def create
    begin
      # Need to change this
      if Game.where(name: params[:name]).empty?
        @game = Game.create(name: params[:name], passcode: params[:passcode])
        @player = Player.create(user_id: current_user.id, game_id: @game.id, nickname: params[:nickname], role: Player::ROLE_GAMEMAKER, alive: true)
        flash[:notice] = 'Game created!'
        redirect_to show_game_path(name: @game.name)
      else
        flash[:notice] = 'Name already exists, please enter another one.'
        redirect_to :back
      end
    rescue
      flash[:notice] = 'Ooops. Something went wrong. Game not created.'
      redirect_to :back
    end
  rescue ActionController::RedirectBackError
    redirect_to root_path
  end

  def join
    @game = Game.where(name: params[:name], passcode: params[:passcode]).first
    if @game.nil?
      flash[:notice] = 'Name or passcode incorrect, please try again.'
      redirect_to :back
    else
      @player = Player.where(user_id: current_user.id, game_id: @game.id).first
      if @player.nil?
        @player = Player.create(user_id: current_user.id, game_id: @game.id, nickname: params[:nickname], role: Player::ROLE_ASSASSIN, alive: true)
        flash[:notice] = 'You have successfully joined the game.'
      else
        flash[:notice] = 'You have already joined the game.'
      end
      # render 'show', name: @game.name
      redirect_to show_game_path(name: @game.name)
    end
  rescue ActionController::RedirectBackError
    redirect_to root_path
  end

  def show
    # Entering each if is an error, else is not
    has_permission = true
    if current_user.nil?
      has_permission = false
    else
      @game ||= Game.where(name: params[:name]).first
      if @game.nil?
        has_permission = false
      else
        @player ||= Player.where(user_id: current_user.id, game_id: @game.id).first
        if @player.nil?
          has_permission = false
        end
      end
    end
    if not has_permission
      flash[:notice] = 'Error: You do not have permission to view the game named ' + params[:name] + '.'
      return redirect_to :back
    end
    @teams = @game.teams.sort_by{|t| t.name}
    @team_id_pairs = Array.new
    @team_id_pairs.push(['none', 0])
    @teams.each do |t|
      @team_id_pairs.push([t.name, t.id])
    end
    @gamemakers, @assassins, @spectators = [], [], []
    @participants = @game.players
    @participants.each do |p|
      if p.is_gamemaker
        @gamemakers.push(p)
      elsif p.is_assassin
        @assassins.push(p)
      else
        @spectators.push(p)
      end
    end
    @assassins_ranked = @assassins.sort_by{|a| [-1 * (a.points || 0), a.user.last_name, a.user.first_name]}
    @survivors = @assassins_ranked.clone.keep_if {|p| p.alive}
    @victims = @assassins_ranked.clone.delete_if {|p| p.alive}
  rescue ActionController::RedirectBackError
    redirect_to root_path
  end

  def join_team
    @player = Player.where(id: params[:player_id]).first
    if params[:team_id] == '0'
      team_name = 'none'
    else
      team = Team.where(id: params[:team_id]).first
      if team
        team_name = team.name
      else
        team_name = nil
      end
    end
    if @player and team_name
      @player.update(team_id: params[:team_id])
      flash[:notice] = 'You have successfully joined team "' + team_name + '".'
      redirect_to show_game_path
    else
      flash[:notice] = 'Error: Failed to join team. Player or team does not exist'
      redirect_to :back
    end
  rescue ActionController::RedirectBackError
    redirect_to root_path
  end

  def generate_assignments
    has_permission = true
    if current_user.nil?
      has_permission = false
    else
      @game ||= Game.where(name: params[:name]).first
      if @game.nil?
        has_permission = false
      else
        @player ||= Player.where(user_id: current_user.id, game_id: @game.id).first
        if @player.nil?
          has_permission = false
        end
      end
    end
    if not has_permission
      flash[:notice] = 'Error: You do not have permission to view the game named ' + params[:name] + '.'
      return redirect_to :back
    end
    @game.generate_clean_assignments
    @game.update(status: Game::STATUS_PENDING)
    redirect_to assignments_path
  rescue ActionController::RedirectBackError
    redirect_to root_path
  end

  def assignments
    # TODO: Check permissions
    @game ||= Game.where(name: params[:name]).first
    @assignments = @game.assignments
  end

  def activate_game
    # TODO: Check permissions
    @game = Game.where(name: params[:name]).first
    @game.activate
    flash[:notice] = 'Game is now active! May the best assassin prevail.'
    redirect_to show_game_path(name: params[:name])
  end

  def kill
    # TODO: Check permissions
    @game = Game.where(name: params[:name]).first
    @player = Player.find(params[:player_id])
    is_reverse_kill = false
    if (params[:commit] == 'Reverse Kill')
      is_reverse_kill = true
    end
    if @game.register_kill(@player, params[:kill_code], is_reverse_kill)
      if @game.is_completed
        flash[:notice] = 'Kill code confirmed. Congratulations, you are the last assassin standing!'
      elsif is_reverse_kill
        flash[:notice] = 'Kill code confirmed. Your assassin has been terminated and a new one is assigned.'
      else
        flash[:notice] = 'Kill code confirmed. Your target has been terminated and a new one is assigned.'
      end
    else
      flash[:notice] = 'Kill code incorrect. Target or assassin not terminated.'
    end
    redirect_to show_game_path(name: params[:name])
  end
end