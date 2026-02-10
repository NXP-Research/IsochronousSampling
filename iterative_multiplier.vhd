-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity iterative_multiplier is
	generic(
		WIDTH_A : natural;
		WIDTH_B : natural
	);
	port(
		clock        : in  std_logic;
		reset        : in  std_logic;
		start        : in  std_logic;
		input_A      : in  unsigned(WIDTH_A - 1 downto 0);
		input_B      : in  unsigned(WIDTH_B - 1 downto 0);
		output       : out unsigned(WIDTH_A + WIDTH_B - 1 downto 0);
		output_valid : out std_logic
	);
end entity iterative_multiplier;

architecture RTL of iterative_multiplier is

	constant output_width : natural := WIDTH_A + WIDTH_B;

	signal accumulator : unsigned(output_width - 1 downto 0);

	type state_type is (IDLE, MULTIPLY);
	signal state : state_type := IDLE;

	signal counter_sig : integer;
	signal valid       : std_logic;

begin
	fsm_process : process(clock, reset) is
		variable counter : integer range 0 to WIDTH_B;
	begin
		if reset = '1' then
			state <= IDLE;
			valid <= '0';
		elsif rising_edge(clock) then
			case state is
				when IDLE =>
					counter := 0;

					accumulator <= (others => '0');
					valid       <= '0';

					if start = '1' then
						state <= MULTIPLY;

						for i in 0 to WIDTH_B loop
							if counter = WIDTH_B or input_B(counter) = '1' then
								exit;
							end if;

							if counter /= WIDTH_B and input_B(counter) = '0' then
								counter := counter + 1;
							end if;
						end loop;
					end if;
				when MULTIPLY =>

					if counter /= WIDTH_B and input_B(counter) = '1' then
						accumulator <= accumulator + shift_left(resize(input_A, output_width), counter);
						counter     := counter + 1;
					end if;

					for i in 0 to WIDTH_B loop
						if counter = WIDTH_B or input_B(counter) = '1' then
							exit;
						end if;

						if counter /= WIDTH_B and input_B(counter) = '0' then
							counter := counter + 1;
						end if;
					end loop;

					if counter = WIDTH_B then
						state <= IDLE;
						valid <= '1';
					end if;
			end case;
		end if;

		counter_sig <= counter;
	end process fsm_process;
	
	output       <= accumulator;
	output_valid <= valid;

	assert_output : process(accumulator, input_A, input_B, valid) is
	begin
		if valid = '1' then
			assert input_A * input_B = accumulator report "Multiplier output is incorrect" severity failure;
		end if;
	end process assert_output;

end architecture RTL;
