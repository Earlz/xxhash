-- =====================================================================
-- Copyright � 2010 by Cryptographic Engineering Research Group (CERG),
-- ECE Department, George Mason University
-- Fairfax, VA, U.S.A.
-- =====================================================================

library ieee;
use ieee.std_logic_1164.all;	   
use ieee.std_logic_arith.all;
use work.sha3_pkg.all;
use work.sha3_jh_package.all;

entity jh_fsm2 is 
	port (
		-- global
		clk : in std_logic;
		rst : in std_logic;
		
		-- datapath
		srdp : out std_logic;	
		
		er : out std_logic; 
		lo : out std_logic;
		sf : out std_logic;
		
		-- control				   
			--fsm1 hand shake signals
		block_ready_clr : out std_logic;		
		msg_end_clr 	: out std_logic;
		
		block_ready		: in std_logic;
		msg_end 		: in std_logic;	
				
			--fsm3 handshake signals
		output_write_set : out std_logic;
		output_busy_set  : out std_logic;
		output_busy		 : in  std_logic
	);							   
end jh_fsm2;

architecture beh of jh_fsm2 is
   type state_type is ( wait_for_sync, idle, process_data, output_data );
   signal cstate, nstate : state_type;
   
   signal pc : std_logic_vector(log2roundnr-1 downto 0);
   signal ziroundnr, li, ei : std_logic;
   signal output_data_s, block_load_s, int_rload, int_rload_init : std_logic;						 
   --================
   
   type state_type2 is (first_block, wait_for_msg_end, wait_for_last_block);
   signal c2state, n2state : state_type2;
   
   
begin	
	-- fsm2 counter
	proc_counter_gen : countern generic map ( N => log2roundnr ) port map ( clk => clk, rst => '0', load => li, en => ei, input => log2roundnrzeros, output => pc);
	ziroundnr <= '1' when pc = conv_std_logic_vector(roundnr-1,log2roundnr) else '0';
	
	-- state process
	cstate_proc : process ( clk )
	begin
		if rising_edge( clk ) then 
			if rst = '1' then
				cstate <= wait_for_sync;
			else
				cstate <= nstate;
			end if;
		end if;
	end process;
	
	nstate_proc : process ( cstate, msg_end, output_busy, block_ready, ziroundnr )
	begin
		case cstate is	 
			when wait_for_sync =>
				nstate <= idle;
			when idle =>
				if ( block_ready = '1' ) then
					nstate <= process_data;
				else
					nstate <= idle;
				end if;	    
			when process_data =>
				if (( ziroundnr = '0' ) or (ziroundnr = '1' and msg_end = '0' and block_ready = '1')
					 or (ziroundnr = '1' and msg_end = '1' and output_busy = '0' and block_ready = '1')) then				
					nstate <= process_data;					
				elsif (ziroundnr = '1' and msg_end = '1' and output_busy = '1') then
					nstate <= output_data;
				else
					nstate <= idle;
				end if;				
			when output_data =>
				if ( output_busy = '1' ) then
					nstate <= output_data;
				elsif (block_ready = '1') then
					nstate <= process_data;			  
				else 
					nstate <= idle;
				end if;				
		end case;
	end process;
	
	
	---- output logic
	--block_read <= '1' when ((cstate = idle) or (cstate = process_data and ziroundnr = '1' and msg_end = '0')) else '0';
	
	output_data_s <= '1' when ((cstate = process_data and ziroundnr = '1' and msg_end = '1' and output_busy = '0') or 
								  (cstate = output_data and output_busy = '0')) else '0';
	output_write_set	<= output_data_s;
	output_busy_set 	<= output_data_s;
	lo 					<= output_data_s;
	
	
	block_load_s		<= '1' when ((cstate = idle and block_ready = '1') or 
									(cstate = process_data and ziroundnr = '1' and msg_end = '0' and block_ready = '1') or
									(cstate = process_data and ziroundnr = '1' and msg_end = '1' and output_busy = '0' and block_ready = '1') or
									(cstate = output_data and block_ready = '1')) else '0';
	block_ready_clr <= block_load_s;
	
	int_rload <= '1' when ((cstate = idle and block_ready = '1') or (cstate = process_data and ziroundnr = '0')) else '0';
	ei <= int_rload;
		
	int_rload_init <= '1' when ((cstate = idle and block_ready = '1') or (cstate = process_data and ziroundnr = '1')) else '0';
	srdp <= int_rload_init;
	li <= int_rload_init;		
	
	er 		<= int_rload or int_rload_init;
	
	msg_end_clr <= '1' when (cstate = process_data and ziroundnr = '1' and msg_end  = '1') else '0';
	
	-- =========================================
	
	-- small fsm
	small_fsm_proc : process ( clk )
	begin
		if rising_edge( clk ) then 
			if rst = '1' then
				c2state <= first_block;
			else
				c2state <= n2state;
			end if;
		end if;
	end process;					   
	
	small_fsm_transition : process ( c2state, block_ready, msg_end, output_data_s ) 
	begin
		case c2state is 	 
			when first_block =>
				if ( block_ready = '1' ) then
					n2state <= wait_for_msg_end;
				else
					n2state <= first_block;
				end if;
			when wait_for_msg_end =>
				if ( msg_end = '1' ) then
					n2state <= wait_for_last_block;
				else
					n2state <= wait_for_msg_end;
				end if;
			when wait_for_last_block =>
				if ( output_data_s = '0' ) then
					n2state <= wait_for_last_block;
				elsif ( block_ready = '1' ) then
					n2state <= wait_for_msg_end;
				else
					n2state <= first_block;
				end if;
		end case;
	end process;		
	
	sf <= '1' when ((c2state = first_block and block_ready = '1') or (c2state = wait_for_last_block and output_data_s = '1' and block_ready = '1')) else '0';
	
end beh;
		
		
		