%% @doc Erlang module for automatically reloading modified modules
%%      during development.
%% @author Loïc Hoguin <essen@dev-extend.eu>
%% @copyright 2011 Dev:Extend
%% 
%% Based on Mochiweb's reloader by Matthew Dempsky <matthew@mochimedia.com>,
%% copyright 2007 Mochi Media, Inc.
%% 
%% Licensed under the MIT License. See the LICENSE file for more information.

-module(ex_reloader).
-behaviour(gen_server).

-export([start/0, start_link/0, stop/0]). %% API.
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]). %% gen_server.

-define(SERVER, ?MODULE).

-type localtime() :: {
	{Year::integer(), Month::1..12, Day::1..31},
	{Hour::0..23, Minute::0..59, Second::0..59}
}.

-record(state, {
	last :: localtime(),
	tref :: term()
}).

-include_lib("kernel/include/file.hrl").

%% API.

-spec start() -> {ok, Pid::pid()}.
start() ->
	gen_server:start({local, ?SERVER}, ?MODULE, [], []).

-spec start_link() -> {ok, Pid::pid()}.
start_link() ->
	gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec stop() -> stopped.
stop() ->
	gen_server:call(?SERVER, stop).

%% gen_server.

init([]) ->
	{ok, TRef} = timer:send_interval(1000, tick),
	{ok, #state{last=erlang:localtime(), tref=TRef}}.

handle_call(stop, _From, State) ->
	{stop, normal, stopped, State};

handle_call(_Request, _From, State) ->
	{reply, ignored, State}.

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info(tick, State) ->
	Now = erlang:localtime(),
	check_changes(State#state.last, Now),
	{noreply, State#state{last=Now}};

handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, State) ->
	{ok, cancel} = timer:cancel(State#state.tref),
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% Internal.

-spec check_changes(From::localtime(), To::localtime()) -> ok | ignore | {error, Reason::atom()}.
%% @doc Check if any of the loaded modules has changed and reload it if necessary.
%% @todo The Erlang compiler deletes existing .beam files if recompiling fails.
%%       Maybe it's worth spitting out a warning here, but it should be limited to just once.
check_changes(From, To) ->
	[case file:read_file_info(Filename) of
		{ok, #file_info{mtime=MTime}} when MTime >= From, MTime < To ->
			reload(Module);
		{ok, _} ->
			ignore;
		{error, enoent} ->
			{error, gone};
		{error, Reason} ->
			error_logger:error_report(io_lib:format("Error reading ~s's file info: ~p", [Filename, Reason])),
			{error, Reason}
	end || {Module, Filename} <- code:all_loaded(), is_list(Filename)].

-spec reload(Module::atom()) -> ok | {error, reload}.
%% @doc Reload the given module.
reload(Module) ->
	code:purge(Module),
	case code:load_file(Module) of
		{module, Module} ->
			error_logger:info_report(io_lib:format("Module ~p has been reloaded.", [Module])),
			ok;
		{error, Reason} ->
			error_logger:error_report(io_lib:format("Error reloading the module ~p: ~p", [Module, Reason])),
			{error, reload}
	end.
