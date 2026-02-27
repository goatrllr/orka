PROJECT = orka
PROJECT_DESCRIPTION = A High-Performance, ETS-Based Process Registry for Erlang/OTP Applications
PROJECT_VERSION = 0.9.0
TEST_DEPS = proper
CT_LOGS_DIR = $(CURDIR)/logs
ERLC_OPTS = +debug_info

include $(if $(ERLANG_MK_FILENAME),$(ERLANG_MK_FILENAME),erlang.mk)
