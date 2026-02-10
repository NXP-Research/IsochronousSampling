-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;

entity IsochronousSampling_NTRUHPS_LW is
	generic(
		DEGREE      : natural := 821;
		DEGREE_BITS : natural := 10;
		RNG_WIDTH   : natural := 16;
		WEIGHT      : natural := 510
	);
	port(
		clock        : in  std_logic;
		reset        : in  std_logic;
		start        : in  std_logic;
		rng_input    : in  std_logic_vector(RNG_WIDTH - 1 downto 0);
		enable_rng   : out std_logic;
		output       : out std_logic_vector(1 downto 0);
		output_valid : out std_logic;
		done         : out std_logic
	);
end entity IsochronousSampling_NTRUHPS_LW;

architecture RTL of IsochronousSampling_NTRUHPS_LW is
	signal rej_start        : std_logic;
	signal rej_rng_input    : std_logic_vector(RNG_WIDTH - 1 downto 0);
	signal rej_enable_rng   : std_logic;
	signal rej_output       : std_logic_vector(DEGREE_BITS - 1 downto 0);
	signal rej_output_valid : std_logic;
	signal rej_done         : std_logic;

	type state_type is (IDLE, REJ_SAMPLE_SUFFLE, DONE_STATE);
	signal state : state_type := IDLE;

	signal c0 : integer range 0 to DEGREE - 1;
	signal c1 : integer range 0 to DEGREE - 1;

begin

	fsm_process : process(clock, reset) is
	begin
		if reset = '1' then
			state        <= IDLE;
			output_valid <= '0';
			done         <= '0';
			rej_start    <= '0';
			output       <= "00";
		elsif rising_edge(clock) then
			case state is
				when IDLE =>
					if start = '1' then
						state     <= REJ_SAMPLE_SUFFLE;
						rej_start <= '1';
					end if;
					c0      <= DEGREE - WEIGHT;
					c1      <= WEIGHT / 2;
				when REJ_SAMPLE_SUFFLE =>
					rej_start <= '0';

					output_valid <= '0';
					if rej_output_valid = '1' then
						if unsigned(rej_output) < c0 then
							output       <= "00";
							output_valid <= '1';
							c0           <= c0 - 1;
						elsif unsigned(rej_output) < c0 + c1 then
							output       <= "01";
							output_valid <= '1';
							c1           <= c1 - 1;
						else
							output       <= "11";
							output_valid <= '1';
						end if;
					end if;

					if rej_done = '1' then
						state <= DONE_STATE;
						done  <= '1';
					end if;
				when DONE_STATE =>
					done  <= '0';
					state <= IDLE;
			end case;
		end if;
	end process fsm_process;

	rej_rng_input <= rng_input;
	enable_rng    <= rej_enable_rng;

	RejSamplingMod_inst : entity work.RejSamplingMod_Iterative
		generic map(
			DEGREE      => DEGREE,
			DEGREE_BITS => DEGREE_BITS,
			RNG_WIDTH   => RNG_WIDTH
		)
		port map(
			clock        => clock,
			reset        => reset,
			start        => rej_start,
			rng_input    => rej_rng_input,
			enable_rng   => rej_enable_rng,
			output       => rej_output,
			output_valid => rej_output_valid,
			done         => rej_done
		);

end architecture RTL;
