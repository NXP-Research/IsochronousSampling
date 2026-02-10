-- Copyright (c) 2021 Florian Bache and Tim Güneysu
-- Copyright (c) 2023 Adrian Marotzke, Georg Land, Jan Richter-Brockmann
-- Copyright 2025 NXP
-- 
-- SPDX-License-Identifier: MIT

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.ALL;
use IEEE.math_real.all;

package interfaces_msk is

	------------
	constant shares   : integer := 4;
	constant TB_WIDTH : natural := 14;

	------------

	type share_num_type is array (TB_WIDTH - 1 downto 0) of natural;

	type t_shared is array (natural range <>) of std_logic_vector;

	type t_shared_trans is array (natural range <>) of std_logic_vector;

	function t_shared_trans_to_t_shared(shared_in_trans : in t_shared_trans; fn_width : in integer; fn_shares : in integer) return t_shared;
	function t_shared_to_t_shared_trans(shared_in : in t_shared; fn_width : in integer; fn_shares : in integer) return t_shared_trans;

	function t_shared_flatten(param : t_shared; width : integer; shares : integer) return std_logic_vector;
	function t_shared_pack(param : std_logic_vector; width : integer; shares : integer) return t_shared;

	function get_rand_req(width : in natural; level : in natural) return natural;

	constant NUMBER_LEVELS : natural := 4;
	--constant level_rand_requirement : natural := get_rand_req(width, 4);

	constant and_pini_mul_nrnd : integer := shares * (shares - 1) / 2;
	constant and_pini_nrnd     : integer := and_pini_mul_nrnd;
	constant nrnd              : integer := and_pini_nrnd;

	subtype t_shared_bit IS std_logic_vector(shares - 1 downto 0);
	subtype t_rand IS std_logic_vector(and_pini_mul_nrnd - 1 downto 0);

	function get_rand_LF(rand_in : in std_logic_vector; width : in natural; level : in natural; offset : in natural; PorG : string) return std_logic_vector;

end interfaces_msk;

package body interfaces_msk is

	function t_shared_trans_to_t_shared(shared_in_trans : in t_shared_trans; fn_width : in integer; fn_shares : in integer) return t_shared is
		variable t_shared_out : t_shared(fn_width - 1 downto 0)(fn_shares - 1 downto 0);
	begin
		for I in 0 to fn_width - 1 loop
			for J in 0 to fn_shares - 1 loop
				t_shared_out(I)(J) := shared_in_trans(J)(I);
			end loop;
		end loop;
		return (t_shared_out);
	end t_shared_trans_to_t_shared;

	function t_shared_to_t_shared_trans(shared_in : in t_shared; fn_width : in integer; fn_shares : in integer) return t_shared_trans is
		variable t_shared_trans_out : t_shared_trans(fn_shares - 1 downto 0)(fn_width - 1 downto 0);
	begin
		for I in 0 to fn_width - 1 loop
			for J in 0 to fn_shares - 1 loop
				t_shared_trans_out(J)(I) := shared_in(I)(J);
			end loop;
		end loop;
		return (t_shared_trans_out);
	end t_shared_to_t_shared_trans;

	function t_shared_flatten(param : t_shared; width : integer; shares : integer)
	return std_logic_vector is
		variable temp : std_logic_vector(width * shares - 1 downto 0);
	begin
		for i in 0 to width - 1 loop
			temp(shares * (i + 1) - 1 downto shares * i) := param(i);
		end loop;

		return temp;
	end function t_shared_flatten;

	function t_shared_pack(param : std_logic_vector; width : integer; shares : integer)
	return t_shared is
		variable temp : t_shared(width - 1 downto 0)(shares - 1 downto 0);
	begin
		for i in 0 to width - 1 loop
			temp(i) := param(shares * (i + 1) - 1 downto shares * i);
		end loop;

		return temp;
	end function t_shared_pack;

	function get_rand_req(width : in natural; level : in natural) return natural is
		variable rand_num : natural := 0;
	begin
		for L in 1 to level loop
			for I in 0 to width - 2 loop
				if I mod 2**L >= 2**(L - 1) then
					rand_num := rand_num + 1;

					if I > 2**L then
						rand_num := rand_num + 1;
					end if;
				end if;
			end loop;
		end loop;
		return (rand_num) * nrnd;
	end function;

	function get_rand_LF(rand_in : in std_logic_vector; width : in natural; level : in natural; offset : in natural; PorG : string) return std_logic_vector is
		variable rand_out : std_logic_vector(nrnd - 1 downto 0);
		variable rand_num : natural := 0;
	begin
		for L in 1 to level loop
			for I in 0 to width - 2 loop
				if I mod 2**L >= 2**(L - 1) then
					if I = offset and L = level and PorG = "G" then
						assert (rand_num + 1) * nrnd - 1 < rand_in'length report "rand_num out of bounds: " & "Rand_offset= " & integer'image(rand_num) & "L= " & integer'image(level) & "offset= " & integer'image(offset) & " " & PorG severity failure;
						rand_out := rand_in((rand_num + 1) * nrnd - 1 downto rand_num * nrnd);
						--assert false report "Rand_offset= " & integer'image(rand_num) & "L= " & integer'image(level) & "offset= " & integer'image(offset) & " " & PorG severity note;
					end if;
					rand_num := rand_num + 1;

					if I > 2**L then
						if I = offset and L = level and PorG = "P" then
							assert (rand_num + 1) * nrnd - 1 < rand_in'length report "rand_num out of bounds: " & "Rand_offset= " & integer'image(rand_num) & "L= " & integer'image(level) & "offset= " & integer'image(offset) & " " & PorG severity failure;
							rand_out := rand_in((rand_num + 1) * nrnd - 1 downto rand_num * nrnd);
							--assert false report "Rand_offset= " & integer'image(rand_num) & "L= " & integer'image(level) & "offset= " & integer'image(offset) & " " & PorG severity note;
						end if;
						rand_num := rand_num + 1;
					end if;
				end if;
			end loop;
		end loop;
		return rand_out;
	end function;
end interfaces_msk;
