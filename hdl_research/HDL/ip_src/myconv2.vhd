---------------------------------------------------------------------------
-- This VHDL file was developed by Daniel Llamocca (2018).  It may be
-- freely copied and/or distributed at no cost.  Any person using this
-- file for any purpose do so at their own risk, and are responsible for
-- the results of such use.  Daniel Llamocca does not guarantee that
-- this file is complete, correct, or fit for any particular purpose.
-- NO WARRANTY OF ANY KIND IS EXPRESSED OR IMPLIED.  This notice must
-- accompany any copy of this file.
--------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
--use ieee.std_logic_unsigned.all;

library work;
use work.pack_xtras.all;

-- Assumption: Input data organized as:
-- Input 0: D(0, B-1 downto 0)
-- Input 1: D(1, B-1 downto 0)
-- Input 2: D(2, B-1 downto 0)
-- Input i: D(i, B-1 downto 0)
-- ...
-- Input N-1: D(N-1, B - 1 downto 0)
entity myconv2 is -- 2 square kernels of equal size.
	generic ( B: INTEGER:= 8; -- bitwidth of each input pixel
	          C: INTEGER:= 8; -- bitwidth of each kernel coefficient
			  N: INTEGER:= 3; -- number of inputs: NxN
              REP: STRING:= "UNSIGNED"); -- Numerical representation for the inputs and output: SIGNED/UNSIGNED
	port ( clock, resetn, E, sclr: std_logic; -- when E=sclr='1' all input registers are cleared.
	       Di: in std_logic_2d (N*N-1 downto 0, B-1 downto 0); -- Here we define the size of the unconstarined array
	       Hi: in std_logic_2d (N*N-1 downto 0, C-1 downto 0); -- Here we define the size of the unconstarined array
	       -- D(0) to D(N*N-1)
	       -- D(0) to D(N-1): first row
	       -- D(N) to D(2*N-1): second row
	       -- ...
	       -- D(N*(N-1)) to D(N*N - 1): last row
		   F: out std_logic_vector (B+C+ceil_log2(N*N)-1 downto 0);
		   v: out std_logic);			 
end myconv2;

architecture structure of myconv2 is

    component adder_tree
        generic (N: INTEGER:= 8;   -- Number of summands
                 B: INTEGER:= 8;  -- Number of bits per summand: B
                    REP: STRING:= "UNSIGNED"); -- Numerical representation for the inputs and output: SIGNED/UNSIGNED
        port ( clock, resetn: in std_logic;
               E: in std_logic;
                 v: out std_logic;
                 X_in: in std_logic_2d(N-1 downto 0, B-1 downto 0);
                 Yo: out std_logic_vector (B+ceil_log2(N) -1 downto 0));
    end component;

	type chunk2D_d is array (N-1 downto 0, N-1 downto 0) of std_logic_vector (B - 1 downto 0);
	signal Dd, D: chunk2D_d;

    type chunk2D_h is array (N-1 downto 0, N-1 downto 0) of std_logic_vector (C - 1 downto 0);
	signal Hd, H: chunk2D_h;
	
	type chunkp2D is array (N-1 downto 0, N-1 downto 0) of std_logic_vector (B+C - 1 downto 0);
	signal P: chunkp2D;
		
    signal Pi: std_logic_2d (N*N-1 downto 0, B+C-1 downto 0);
    signal E_q, v_d: std_logic;
    
    signal Fd: std_logic_vector (B+C+ceil_log2(N*N)-1 downto 0);
    
begin

-- Di(0) Di(1)   ... Di(N-1)
-- Di(N) Di(N+1) ... Di(2*N-1)
-- ...
-- Di(N*(N-1)) Di(N*(N-1) + 1) ... Di(N*N-1)

-- D(0,0) D(0,1) ... D(0,N-1)
-- D(1,0) D(1,1) ... D(1,N-1)
-- ...
-- D(N-1,0) D(N-1,1) ... D(N-1,N-1)

-- Converting std_logic_2d signals to 2D vectors
si: for i in 0 to N-1 generate -- row index for Di
        sj: for j in 0 to N-1 generate -- column index for Di
              sk: for k in 0 to B-1 generate
                    Dd(i,j)(k) <= Di(i*N + j,k); -- note how indexing is different
                    Hd(i,j)(k) <= Hi(i*N + j,k); -- note how indexing is different
                  end generate;
            end generate;
    end generate;

-- Registers for all the inputs and products.
mi: for i in 0 to N-1 generate
        mj: for j in 0 to N-1 generate
                ra: my_rege generic map (N => B)
                    port map (clock => clock, resetn => resetn, E => E, sclr => sclr, D => Dd(i,j), Q => D(i,j));
                rb: my_rege generic map (N => C)
                    port map (clock => clock, resetn => resetn, E => E, sclr => sclr, D => Hd(i,j), Q => H(i,j));
                
                ru: if REP = "UNSIGNED" generate
                       P(i,j) <= unsigned(D(i,j))*unsigned(H(i,j));
                    end generate;
                
                rs: if REP = "SIGNED" generate
                       P(i,j) <= signed(D(i,j))*signed(H(i,j));
                    end generate;
                
            end generate;
    end generate;
  
-- Turning P(i,j) into a std_logic_2d signal for the Adder Tree   
qi: for i in 0 to N-1 generate -- row index for Di
            qj: for j in 0 to N-1 generate -- column index for Di
                  qk: for k in 0 to B+C-1 generate
                         Pi(i*N + j,k) <= P(i,j)(k); -- note how indexing is different
                      end generate;
                end generate;
        end generate;    
 
-- Adding up all the products
at: adder_tree generic map (N => N*N, B => B+C, REP => REP)
    port map (clock => clock, resetn => resetn, E => E_q, v => v_d, X_in => Pi, Yo => Fd);

dE: dffe port map (d => E, clrn => resetn, prn => '1', clk => clock, ena => '1', q => E_q);
dv: dffe port map (d => v_d, clrn => resetn, prn => '1', clk => clock, ena => '1', q => v);

-- Output Register
ro: my_rege generic map (N => B+C+ceil_log2(N*N))
    port map (clock => clock, resetn => resetn, E => v_d, sclr => '0', D => Fd, Q => F);
        
end structure;