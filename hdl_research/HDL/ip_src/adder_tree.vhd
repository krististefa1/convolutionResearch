---------------------------------------------------------------------------
-- This VHDL file was developed by Daniel Llamocca.  It may be
-- freely copied and/or distributed at no cost.  Any persons using this
-- file for any purpose do so at their own risk, and are responsible for
-- the results of such use.  Daniel Llamocca does not guarantee that
-- this file is complete, correct, or fit for any particular purpose.
-- NO WARRANTY OF ANY KIND IS EXPRESSED OR IMPLIED.  This notice must
-- accompany any copy of this file.
--------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library work;
use work.pack_xtras.all;

-- Generic pipelined adder tree: Number of register levels: ceil_log2(N)
-- Note that numbers are treated as in 2's complement representation
-- X_in: 2d array (see pack_xtras.vhd for definition):
-- X_in(0,0) X_in(0,1) X_in(0,2) ... X_in (0,B-1)
-- X_in(1,0) X_in(1,1) X_in(1,2) ... X_in (1,B-1)
-- X_in(2,0) X_in(2,1) X_in(2,2) ... X_in (2,B-1)
-- ...
-- X_in(N-1,0) X_in(N-1,1) X_in(N-1,2) ... X_in (N-1,B-1)

-- Each row represents a B-bit vector. So there are N B-bit vector
-- The output Yo is the sum of all the N B-bit vectors, its size is: B+ceil_log2(N) bits
-- SUGGESTION: To properly use this core, create a signal of type: array (N-1 downto 0) of std_logic_vector (B-1 downto 0)
--             This type of signal is easier to manipulate. Then, for the 'adder_tree' instantiation, convert the
--             signal of type 'array (N-1 downto 0) of std_logic_vector(B-1 downto 0)' to a signal of type 'std_logic_2d'
-- The reason this 'adder_tree' core does not have a signal of type 'array (N-1 downto 0) of std_logic_vector(B-1 downto 0)'
-- as input (which would make everything simpler) is because VHDL does not allow for generic data types that can be used
-- throughout all the VHDL files in a project. Thus, we settle to use a 'std_logic_2d' signal.
	
entity adder_tree is
	generic (N: INTEGER:= 8;   -- Number of summands
	         B: INTEGER:= 8;  -- Number of bits per summand: B
		     REP: STRING:= "UNSIGNED"); -- Numerical representation for the inputs and output: SIGNED/UNSIGNED
	port ( clock, resetn: in std_logic;
	       E: in std_logic;
			 v: out std_logic;
			 X_in: in std_logic_2d(N-1 downto 0, B-1 downto 0);
			 Yo: out std_logic_vector (B+ceil_log2(N) -1 downto 0));
end adder_tree;

architecture structure of adder_tree is

	type chunk_X is array (N-1 downto 0) of std_logic_vector(B-1 downto 0);
	signal X: chunk_X;

	constant L_fbk: INTEGER:=  B;  -- Max # of bits of each summand (N additions)
	constant LV: INTEGER:= ceil_log2(N); -- number of levels of the array of adders that adds each FIR block output
	constant XL: int_vector(LV downto 0):= Get_X(LV,N);
	
	type chunk_3D is array (natural range <>, natural range <>) of std_logic_vector(L_fbk + LV - 1 downto 0); 
	signal yf: chunk_3D(LV downto 0, N - 1 downto 0);
	signal yf_q: chunk_3D(LV - 1 downto 0, N - 1 downto 0);
	
begin

a0: assert (REP = "SIGNED" or REP = "UNSIGNED")
    report "REP can only be SIGNED or UNSIGNED"
	 severity error;
	 
	fi: for i in 0 to N-1 generate
		   fj: for j in 0 to B-1 generate
					 X(i)(j) <= X_in(i,j);					
			    end generate;
				 yf(0,i)(B-1 downto 0) <= X(i);
		 end generate;

-- Now we need to add all the outputs yf(0,i) = X(i)
gi: for i in 1 to LV generate -- If N = 1 --> LV = 0 and this loop is not run
		-- The registers are created:
		gk: for k in 0 to XL(i-1)-1 generate
					rk: my_rege generic map (N => L_fbk + (i-1))
					    port map (clock => clock, resetn => resetn, E => '1', sclr => '0', D => yf(i-1,k)(L_fbk + (i-1) - 1 downto 0), Q => yf_q(i-1,k)(L_fbk + (i-1) - 1 downto 0));
					
               ss: if REP = "UNSIGNED" generate
								yf_q(i-1,k)(L_fbk + i-1) <= '0'; -- zero extension
                   end generate;
               
               su: if REP = "SIGNED" generate					
								yf_q(i-1,k)(L_fbk + i-1) <= yf_q(i-1,k)(L_fbk + (i-1) - 1); -- sign extension, this would be 'yf_p'
						 end generate;
			 end generate;

		-- Adders are created:
		gj: for j in 0 to XL(i)-2 generate				
					gjs: my_addsub generic map (N => L_fbk + i)
					     port map (addsub => '0', x => yf_q(i-1,2*j)(L_fbk + i - 1 downto 0), y => yf_q(i-1,2*j + 1)(L_fbk + i - 1 downto 0), s => yf(i,j)(L_fbk + i - 1 downto 0));
			 end generate;

		gjp: for j in XL(i)-1 to XL(i)-1 generate
					gjps: if (XL(i-1) rem 2 = 0) generate -- X(i-1) is even?, is the same as asking 2*X(i) = X(i-1)
								g6: my_addsub generic map (L_fbk + i)
								    port map (addsub => '0', x => yf_q(i-1, 2*j)(L_fbk + i - 1 downto 0), y => yf_q(i-1, 2*j + 1)(L_fbk + i - 1 downto 0), s => yf(i,j)(L_fbk + i - 1 downto 0));
							 end generate;
					 
					gjpns: if (XL(i-1) rem 2 = 1) generate -- X(i-1) is odd?, is the same as asking 2*X(i) /=X(i-1)
									yf(i,j)(L_fbk + i - 1 downto 0) <= yf_q(i-1,2*j)(L_fbk + i - 1 downto 0);
							 end generate;
			  end generate;
					 
	 end generate;

-- yf(LV,0): final adder tree output (B+ ceil_log2(N) bits)
   Yo <= yf (LV,0);
	
-- Shift register for E:   
	gsl: my_pashiftreg generic map (N => ceil_log2(N), DIR => "RIGHT")
	     port map (clock => clock, resetn => resetn, din => E, E => '1', s_l => '0', D => (others => '0'), shiftout => v);
end structure;

