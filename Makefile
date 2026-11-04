# 顶层：make stage1 / make check
stage1:
	$(MAKE) -C core/stage1

check:
	@for f in core/stage2/harnoa.sh core/stage2/lib/*.sh boot/mkimg.sh tools/*.sh; do sh -n $$f || exit 1; done
	@for b in boards/*/; do sh tools/check-board.sh $$b || exit 1; done

.PHONY: stage1 check
