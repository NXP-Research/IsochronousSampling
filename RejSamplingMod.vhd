-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;

entity RejSamplingMod is
	generic(
		DEGREE      : natural := 761;
		DEGREE_BITS : natural := 10;
		RNG_WIDTH   : natural := 16
	);
	port(
		clock        : in  std_logic;
		reset        : in  std_logic;
		start        : in  std_logic;
		rng_input    : in  std_logic_vector(RNG_WIDTH - 1 downto 0);
		enable_rng   : out std_logic;
		output       : out std_logic_vector(DEGREE_BITS - 1 downto 0);
		output_valid : out std_logic;
		done         : out std_logic
	);
end entity RejSamplingMod;

architecture RTL of RejSamplingMod is
	type t_array_type is array (0 to DEGREE - 1) of unsigned(RNG_WIDTH downto 0);

	function compute_t_array(L : natural; n : natural)
	return t_array_type is
		variable t_array_temp : t_array_type                 := (others => (others => '0'));
		constant two_power_L  : unsigned(RNG_WIDTH downto 0) := to_unsigned(2**L, RNG_WIDTH + 1);
	begin
		for i in 0 to n - 1 loop
			t_array_temp(i) := two_power_L mod (n - i);
		end loop;

		return t_array_temp;
	end function compute_t_array;

	constant t_array : t_array_type := compute_t_array(RNG_WIDTH, DEGREE);

	type state_type is (IDLE, START_PIPE, RUNNING, CLEANUP, COMPLETE);
	signal state_rejmod : state_type := IDLE;

	signal x : unsigned(RNG_WIDTH - 1 downto 0);
	signal s : unsigned(DEGREE_BITS - 1 downto 0);

	constant pipeline_length : natural := 2;
	type m_pipeline_type is array (0 to pipeline_length - 1) of unsigned(RNG_WIDTH + DEGREE_BITS - 1 downto 0);
	signal m                 : m_pipeline_type;

	signal m_mod_l : unsigned(RNG_WIDTH - 1 downto 0);

	signal counter : integer range 0 to DEGREE;

	signal counter_delay_input : integer range 0 to DEGREE;

	type counter_pipeline_type is array (0 to pipeline_length) of integer range 0 to DEGREE;

	signal counter_delay : counter_pipeline_type;

	signal pipeline_valid : std_logic_vector(0 to pipeline_length);

	signal valid_sample : std_logic;

	signal si_address_a  : std_logic_vector(DEGREE_BITS - 1 downto 0);
	signal si_data_out_a : std_logic_vector(DEGREE_BITS - 1 downto 0);
	signal si_address_b  : std_logic_vector(DEGREE_BITS - 1 downto 0);
	signal si_write_b    : std_logic;
	signal si_data_in_b  : std_logic_vector(DEGREE_BITS - 1 downto 0);

	signal fifo_wr_en      : std_logic;
	signal fifo_wr_data    : std_logic_vector(DEGREE_BITS - 1 downto 0);
	signal fifo_rd_en      : std_logic;
	signal fifo_rd_valid   : std_logic;
	signal fifo_rd_data    : std_logic_vector(DEGREE_BITS - 1 downto 0);
	signal fifo_empty      : std_logic;
	signal fifo_empty_next : std_logic;
	signal fifo_full       : std_logic;
	signal fifo_full_next  : std_logic;

	signal first_run_done : std_logic;

begin
	fsm_process : process(clock, reset) is
	begin
		if reset = '1' then
			state_rejmod   <= IDLE;
			--x              <= (others => '0');
			--s              <= (others => '0');
			fifo_rd_en     <= '0';
			done           <= '0';
			output_valid   <= '0';
			enable_rng     <= '0';
			first_run_done <= '0';
		elsif rising_edge(clock) then
			case state_rejmod is
				when IDLE =>
					if start = '1' then
						state_rejmod <= START_PIPE;
						enable_rng   <= '1';
					end if;

					counter           <= 0;
					pipeline_valid(0) <= '0';
					done              <= '0';
				when START_PIPE =>
					counter <= counter + 1;
					x       <= unsigned(rng_input);
					s       <= to_unsigned(DEGREE - counter, DEGREE_BITS);

					pipeline_valid(0) <= '1';

					if counter = pipeline_length then
						state_rejmod <= RUNNING;
					end if;

					if first_run_done = '1' then
						output_valid <= '1';
					end if;
				when RUNNING =>
					counter <= counter + 1;
					x       <= unsigned(rng_input);
					s       <= to_unsigned(DEGREE - counter, DEGREE_BITS);

					if counter = DEGREE - 2 then
						fifo_rd_en <= '1';
					end if;

					if counter = DEGREE - 1 then
						state_rejmod <= CLEANUP;
						counter      <= 0;

					end if;

				when CLEANUP =>
					x <= unsigned(rng_input);
					s <= DEGREE - unsigned(fifo_rd_data);

					output_valid <= '0';

					if fifo_rd_valid = '1' then
						pipeline_valid(0) <= '1';
					else
						pipeline_valid(0) <= '0';
					end if;

					if fifo_empty = '1' then
						counter <= counter + 1;
					end if;

					if fifo_wr_en = '1' then
						counter <= 0;
					end if;

					if counter = pipeline_length + 1 and fifo_wr_en /= '1' then
						state_rejmod   <= COMPLETE;
						enable_rng     <= '0';
						fifo_rd_en     <= '0';
						counter        <= 0;
						first_run_done <= '1';
					end if;
				when COMPLETE =>
					state_rejmod <= IDLE;
					done         <= '1';
					output_valid <= '0';
			end case;

			pipeline_valid(1 to pipeline_length) <= pipeline_valid(0 to pipeline_length - 1);
		end if;
	end process fsm_process;

	m(0)                        <= x * s when rising_edge(clock);
	m(1 to pipeline_length - 1) <= m(0 to pipeline_length - 2) when rising_edge(clock);

	m_mod_l <= m(pipeline_length - 1)(RNG_WIDTH - 1 downto 0);

	counter_delay_input <= counter when state_rejmod = RUNNING or state_rejmod = START_PIPE
	                       else to_integer(unsigned(fifo_rd_data)) when state_rejmod = CLEANUP and fifo_rd_valid = '1'
	                       else 0;

	counter_delay(0)                    <= counter_delay_input when rising_edge(clock);
	counter_delay(1 to pipeline_length) <= counter_delay(0 to pipeline_length - 1) when rising_edge(clock);

	valid_sample <= '1' when m_mod_l >= t_array(counter_delay(pipeline_length - 1)) and (state_rejmod = RUNNING or state_rejmod = CLEANUP) else '0';

	si_address_b <= std_logic_vector(to_unsigned(counter_delay(pipeline_length), DEGREE_BITS));
	si_data_in_b <= std_logic_vector(shift_right(m(pipeline_length - 1), RNG_WIDTH)(DEGREE_BITS - 1 downto 0));
	si_write_b   <= valid_sample when pipeline_valid(pipeline_length) = '1' else '0';

	fifo_wr_data <= std_logic_vector(to_unsigned(counter_delay(pipeline_length), DEGREE_BITS));
	fifo_wr_en   <= not valid_sample when state_rejmod = RUNNING OR state_rejmod = CLEANUP else '0';

	si_address_a <= std_logic_vector(to_unsigned(counter, DEGREE_BITS));
	output       <= si_data_out_a;

	SDP_dist_RAM_inst : entity work.SDP_RAM
		generic map(
			ADDRESS_WIDTH => DEGREE_BITS,
			DATA_WIDTH    => DEGREE_BITS
		)
		port map(
			clock      => clock,
			address_a  => si_address_a,
			data_out_a => si_data_out_a,
			address_b  => si_address_b,
			write_b    => si_write_b,
			data_in_b  => si_data_in_b
		);

	-- fifo memory to keep track of rejected samples
	FIFO_buffer_inst : entity work.FIFO_buffer
		generic map(
			RAM_WIDTH => DEGREE_BITS,
			RAM_DEPTH => 128
		)
		port map(
			clock      => clock,
			reset      => reset,
			wr_en      => fifo_wr_en,
			wr_data    => fifo_wr_data,
			rd_en      => fifo_rd_en,
			rd_valid   => fifo_rd_valid,
			rd_data    => fifo_rd_data,
			empty      => fifo_empty,
			empty_next => fifo_empty_next,
			full       => fifo_full,
			full_next  => fifo_full_next
		);

end architecture RTL;
