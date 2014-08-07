-- =====================================================================
-- Copyright � 2010-2011 by Cryptographic Engineering Research Group (CERG),
-- ECE Department, George Mason University
-- Fairfax, VA, U.S.A.
-- =====================================================================

library IEEE;
use ieee.std_logic_1164.all;			
use ieee.std_logic_unsigned.all; 
use ieee.std_logic_arith.all;
use work.sha3_pkg.all;
use work.groestl_pkg.all;

-- Groestl fsm1 is responsible for controlling input interface 

entity groestl_fsm1 is	 
	generic (mw :integer :=GROESTL_DATA_SIZE_SMALL);
	port (
	io_clk 				: in std_logic;
	rst 				: in std_logic;		
	c					: in std_logic_vector(w-1 downto 0);
	ein 				: out std_logic;   
	wr_c 				: out std_logic; 
	wr_seg 				: out std_logic; 	
	wr_len				: out std_logic;
	sync 				: in std_logic;
	load_next_block		: in std_logic;	 
	done 				:in std_logic;	 
	final_segment		: in std_logic;	
	last_block			:in std_logic; 
	block_ready_set 	: out std_logic;   
	wfl2				: out std_logic; 
	ls_rs_set			: out std_logic;
	msg_end 			: in std_logic;
	msg_end_set 		: out std_logic;
	src_ready 			: in std_logic;
	src_read    		: out std_logic);
end groestl_fsm1;					   

architecture nocounter of groestl_fsm1 is	
constant mwseg			: integer := mw/w;
constant log2mwseg 		: integer := log2( mwseg );

-- compare			  							 
	signal zc0, zcblock : std_logic;

	-- counter
	signal zjfin, lj, ej : std_logic;		 
	signal wc : std_logic_vector(log2mwseg-1 downto 0);

	-- fsm sigs
	type state_type is ( reset, idle, wait_for_header1, wait_dbg, wait1, wait_for_header2, wait2, check_len, load_block, wait_for_load1, wait_for_load2, wait_for_load3, last );
	signal cstate_fsm1, nstate : state_type; 
	signal zero : std_logic_vector(log2mwseg-1 downto 0):=(others=>'0');		
	signal zc0_wire, zcblock_wire :std_logic;
begin	 

	
	-- compare sigs
	zc0_wire <= '1' when c = 0 else '0';	
	zcblock_wire <= '1' when (c = mw) or (c < mw) else '0';	 
		
	zc0_reg 	: d_ff port map ( clk => io_clk, ena => VCC, rst => GND, d => zc0_wire, q => zc0 );
	zcblock_reg : d_ff port map ( clk => io_clk, ena => VCC, rst => GND, d => zcblock_wire, q => zcblock );
	
	
	-- fsm1 counter		
	word_counter_gen : countern generic map ( n => log2mwseg ) port map ( clk => io_clk, rst => rst, load => lj, en => ej, input => zero, output => wc);
	zjfin <= '1' when wc = conv_std_logic_vector(mwseg-1,log2mwseg) else '0';				
	
	-- state process
	cstate_proc : process ( io_clk )
	begin
		if rising_edge( io_clk ) then 
			if rst = '1' then
				cstate_fsm1 <= idle;
			else
				cstate_fsm1 <= nstate;
			end if;
		end if;
	end process;
	
	nstate_proc : process ( cstate_fsm1, src_ready, load_next_block, zjfin, zc0, zcblock, sync, last_block, done, final_segment, msg_end  )
	begin
		case cstate_fsm1 is
			when idle =>
				nstate <= wait_for_header1;
			
			when wait_for_header1 =>
				if ( src_ready = '1' ) then
					nstate <= wait_for_header1;
				else
					nstate <= wait1;
				end if;		
				
			when wait1=> 
				if final_segment='1' then 
					nstate <= wait_for_header2;	 
				else 
					nstate <= check_len;
				end if;
				
							
			when wait_for_header2=>
				if ( src_ready = '1' ) then
					nstate <= wait_for_header2;
				else
					nstate <= wait2;
				end if;	
			
			when wait2 => 
					nstate <= check_len;	
				
				
			when check_len =>
				if (zc0 = '1') then
				 	nstate <= wait_for_header1;
				elsif (load_next_block = '1') then
					nstate <= load_block;
				else
					nstate <= check_len;
				end if;	 	
			

							
			when load_block =>	
				if done='1' then
					nstate <= idle;
				elsif ((src_ready = '1') or (src_ready = '0' and zjfin = '0')) then
					nstate <= load_block; 					
				elsif ( zcblock = '1' or  last_block='1' ) then
					nstate <= wait_for_load3; --- here change
				else
					nstate <= wait_for_load2;				
				end if;							
			when wait_for_load1 =>
				if (load_next_block = '1') then
					nstate <= idle;
				else
					nstate <= wait_for_load1;
				end if;	  
			when wait_for_load2 =>	 
			if last_block='1' then 
					nstate <= wait_for_load3;
				elsif (load_next_block = '1' ) then
					nstate <= load_block;
				else
					nstate <= wait_for_load2;
				end if;	   
				
			when wait_for_load3 =>
				if done='1' then
					nstate <= last;--idle;	
				else 
					nstate <= wait_for_load3;
				end if;	
				
			when last => 
				if ( src_ready = '1' ) then
					nstate <= last;
				else
					nstate <= idle;
				end if;
			
			when others => 
				nstate <= idle;
		end case;
	end process;
	
	-- fsm output
	
	src_read <= '1' when 	((cstate_fsm1 = wait1 and src_ready = '0') or  			--or(cstate_fsm1 = wait2  and src_ready = '0')											
							(cstate_fsm1 = check_len and zc0 = '0' and load_next_block = '1' and src_ready = '0' ) or
							(cstate_fsm1 = wait_for_load2 and load_next_block = '1' and src_ready = '0' ) or
							(cstate_fsm1 = load_block and src_ready = '0')) or(cstate_fsm1 = last  and src_ready = '0') else '0';
		
	ein <= '1' when ( (cstate_fsm1 = wait1 and src_ready = '0') or 	  --(cstate_fsm1 = wait2  and src_ready = '0')or
					(cstate_fsm1 = check_len and zc0 = '0' and load_next_block = '1' and src_ready = '0' ) or
					(cstate_fsm1 = wait_for_load2 and load_next_block = '1' and src_ready = '0' ) or
				 	(cstate_fsm1 = load_block and src_ready = '0')) else '0';
						 
	ej <= '1' when 	((cstate_fsm1 = check_len and zc0 = '0' and load_next_block = '1' and src_ready = '0' ) or
					(cstate_fsm1 = wait_for_load2 and load_next_block = '1' and src_ready = '0' ) or
				 	(cstate_fsm1 = load_block and src_ready = '0' and zjfin = '0')) else '0';	
						 
    block_ready_set <= '1' when ((cstate_fsm1 = load_block and src_ready = '0' and zjfin = '1')) else '0';
						
	--msg_end_set <= '1' when (cstate_fsm1 = check_len and zc0 = '1')  else '0';
	msg_end_set <= '1' when (cstate_fsm1 = wait_for_header1 and last_block='1')  else '0';	
		
	lj <= '1' when ((cstate_fsm1 = reset) or 
					(cstate_fsm1 = check_len and zc0 = '0' and load_next_block = '1' and src_ready = '1') or
					(cstate_fsm1 = wait_for_load2 and load_next_block = '1' and  src_ready = '1') or
					(cstate_fsm1 = load_block and src_ready = '0' and zjfin = '1' )) else '0';  
		
	
		
	wr_c <= '1' when (cstate_fsm1 = wait_for_header1 and src_ready='0') else '0';
	wr_seg <= '1' when (cstate_fsm1 = wait2) else '0';
		
	wr_len <= '1' when (cstate_fsm1 = wait1) else '0';--and (msg_end='1')	
		
	wfl2 <= '1' when (cstate_fsm1 = wait_for_load2)	else '0';	   
		
	ls_rs_set <= '1' when (cstate_fsm1=wait1 and final_segment='1')	else '0';	
		
end nocounter;