library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.pack_xtras.all;

-- Interface for pSize = 8 and Kernel Size = 3x3
entity myconv2_ip is
        port (  clock: in std_logic;
                rst: in std_logic; -- high-level reset                
                DI: in std_logic_vector (31 downto 0);
                DO: out std_logic_vector (31 downto 0);
                ofull, iempty: in std_logic;
                owren, irden: out std_logic); 
end myconv2_ip;

architecture structure of myconv2_ip is

    component myconv2 -- 2 square kernels of equal size.
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
    end component;

    component my_rege
       generic (N: INTEGER:= 4);
        port ( clock, resetn: in std_logic;
               E, sclr: in std_logic; -- sclr: Synchronous clear
                 D: in std_logic_vector (N-1 downto 0);
               Q: out std_logic_vector (N-1 downto 0));
    end component;
	
    constant B: integer:= 8;
	constant C: integer:= 8;
	constant N: integer:= 3;
	constant OSIZE: integer:= B+C+ceil_log2(N*N);

	signal F: std_logic_vector (OSIZE -1 downto 0);
	signal D_i: std_logic_2d (N*N-1 downto 0, B-1 downto 0);
	signal Hi: std_logic_2d (N*N-1 downto 0, C-1 downto 0); 
	
	type chunk2D_d is array (N-1 downto 0, N-1 downto 0) of std_logic_vector (B - 1 downto 0);
    signal D: chunk2D_d;

    type chunk2D_h is array (N-1 downto 0, N-1 downto 0) of std_logic_vector (C - 1 downto 0);
    signal H: chunk2D_h;
    
	type state is (S1, S2, S3, S4);
	signal y, ys: state;
	
	signal v,E: std_logic;

    signal Eri: std_logic_vector (1 downto 0);
    signal XA, XB: std_logic_vector (31 downto 0);
    signal XC: std_logic_vector (7 downto 0);
    signal resetn: std_logic;
    	    
begin

resetn <= not (rst);

DO (31 downto OSIZE) <= (others => '0');
DO (OSIZE -1 downto 0) <= F;

-- Converting std_logic_2d signals to 2D vectors
si: for i in 0 to N-1 generate -- row index for Di
        sj: for j in 0 to N-1 generate -- column index for Di
              sk: for k in 0 to B-1 generate
                    D_i(i*N + j,k) <= D(i,j)(k); -- note how indexing is different
                    Hi(i*N + j,k) <= H(i,j)(k); -- note how indexing is different
                  end generate;
            end generate;
    end generate;
   
	
-- ****************************
-- Controlling the Input side:	
-- **************************** 
    Transitions: process (rst, clock, iempty, ofull)
		begin
			if rst = '1' then
				y <= S1;
			elsif (clock'event and clock = '1') then
				case y is
					when S1 =>
					    if iempty = '1' then y <= S2; else y <= S1; end if;
					    
					when S2 =>
					    if iempty = '0' and ofull = '0' then
					       y <= S3;
					    else
					       y <= S2;
					    end if;

					when S3 =>
					    if iempty = '0' and ofull = '0' then
					       y <= S4;
					    else
					       y <= S3;
					    end if;

					when S4 =>
					    if iempty = '0' and ofull = '0' then
					       y <= S2;
					    else
					       y <= S4;
					    end if;					                            	
				end case;
			end if;
		end process;
				
		Outputs: process (y,iempty, ofull)
		begin
			-- Initialization of signals
			Eri <= (others => '0'); irden <= '0';
			E <= '0';

			case y is
				when S1 =>

				when S2 =>
                    if iempty = '0' and ofull = '0' then
                        irden <= '1'; Eri(1) <= '1';
					end if;				

				when S3 =>
                    if iempty = '0' and ofull = '0' then
                        irden <= '1'; Eri(0) <= '1';
					end if;				

            	when S4 =>
                    if iempty = '0' and ofull = '0' then
                        irden <= '1'; E <= '1';
					end if;									
				end case;
			
		end process;


-- ****************************
-- Controlling the Output side:
-- ****************************	 
		Transitions_o: process (rst, clock, v)
		begin
			if rst = '1' then
				ys <= S1;
			elsif (clock'event and clock = '1') then
				case ys is
					when S1 =>
						if v = '1' then ys <= S1; else ys <= S2; end if;
						
					when S2 =>
                        ys <= S2;
                        
                    when others =>
							
				end case;
			end if;
		end process;
				
		Outputs_o: process (ys, v)
		begin
			-- Initialization of signals
			owren <= '0';
			case ys is
				when S1 =>

				when S2 =>
					if v = '1' then owren <= '1'; end if;
					
			    when others =>
			end case;		
		end process;
	
	-- The input is 72 bits
	-- DI = XA(31..0): first 4 pixels: P(0) to P(3):  |D(0)|D(1)|D(2)|D(3)|
	-- DI = XB(31..0): second 4 pixels: P(4) to P(7): |D(4)|D(5)|D(6)|D(7)|
	-- DI(7..0) = XC(7..0): last pixel: P(8):         | 0  | 0  | 0  |D(8)|
	
	D(0,0) <= XA (31 downto 24); D(0,1) <= XA (23 downto 16); D(0,2) <= XA (15 downto 8);
	D(1,0) <= XA (7 downto 0);   D(1,1) <= XB (31 downto 24); D(1,2) <= XB (23 downto 16);
	D(2,0) <= XB (15 downto 8);  D(2,1) <= XB (7 downto 0);   D(2,2) <= XC ( 7 downto  0);
		
	H(0,0) <= x"02"; H(0,1) <= x"0B"; H(0,2) <= x"02";
    H(1,0) <= x"05"; H(1,1) <= x"0E"; H(1,2) <= x"05";
    H(2,0) <= x"02"; H(2,1) <= x"0B"; H(2,2) <= x"02";

-- XA: first 4 pixels
-- XB: second 4 pixels
-- XC: last pixel

ri0: my_rege generic map (N => 32)
     port map (clock => clock, resetn => resetn, E => Eri(1), sclr => '0', D => DI , Q => XA);

ri1: my_rege generic map (N => 32)
     port map (clock => clock, resetn => resetn, E => Eri(0), sclr => '0', D => DI , Q => XB);

    XC <= DI(7 downto 0);
    
g1: myconv2 generic map (B => B, C => C, N => N, REP => "UNSIGNED")
    port map (clock => clock, resetn => resetn, E => E, sclr => '0', Di => D_i, Hi => Hi, F => F, v => v);
	 
end structure;

