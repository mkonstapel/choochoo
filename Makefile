all:
	cd .. && tar --no-recursion -cf choochoo/choochoo.tar choochoo choochoo/*.nut

clean:
	@rm -f choochoo.tar
