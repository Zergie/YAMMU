PYTHON := python3
SEND := FusionAddons/FusionHeadless/.venv/bin/python FusionAddons/FusionHeadless/send.py

.PHONY: setup clean
all: \
	FusionAddons/FusionHeadless/.venv/lib64/python3.12/site-packages/pygments/__init__.py \
	obj/components.printed.json \
	obj/components.notprinted.json \
	Images/render_1.png

FusionAddons/FusionHeadless/.venv/lib64/python3.12/site-packages/pygments/__init__.py: FusionAddons/FusionHeadless/requirements.txt FusionAddons/FusionHeadless/Makefile
	cd FusionAddons/FusionHeadless && make && cd ../..

obj/yammu.files.json: 
	mkdir -p obj && \
	$(SEND) --get /files --jmespath "result[?parentFolder.name=='YAMMU']" --output $@

obj/Assembly.json: obj/yammu.files.json
	$(SEND) --file $< --jmespath "[?name == 'Assembly'].{id:id}" \
		| $(SEND) --get /files --file - --jmespath "result" --output $@

obj/components.json: obj/Assembly.json
	$(SEND) --file $< --jmespath "{open:id}" \
		| $(SEND) --get /document --file - && \
	$(SEND) --get /components --jmespath "result" --output $@

obj/components.printed.json: obj/components.json
	$(SEND) --file $< \
		--jmespath "values(@)[?bodies[?material == 'ABS Plastic (Voron Black)' || material == 'ABS Plastic (Voron Red)']]" \
		--jmespath "[?!contains(name, 'Body')]" \
		--jmespath "[].{id:id, name: name, count: count, bodies: bodies[?material == 'ABS Plastic (Voron Black)' || material == 'ABS Plastic (Voron Red)'].{id:id, name: name, color: color}}" --plain \
		| $(SEND) --file - --match-with-files "STLs" --accent-color "C43527FF" --output $@

obj/components.notprinted.json: obj/components.json
	$(SEND) --file $< \
		--jmespath "values(@)[?bodies[?material != 'ABS Plastic (Voron Black)' && material != 'ABS Plastic (Voron Red)']]" \
		--output $@

Images/render_1.png: obj/yammu.files.json
	mkdir -p Images && \
	$(SEND) --file $< \
		--jmespath "[?name == 'Assembly'].{open:id}" \
		--output $@
	$(SEND) --get /render \
		--data '{"show": "all", "hide": "Tools", "view": "Render_1", "focalLength": 200, "quality": "75", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_ebay.png: obj/yammu.files.json
	mkdir -p Images && \
	$(SEND) --file $< \
		--jmespath "[?name == 'Assembly'].{open:id}" \
		--output $@
	$(SEND) --get /render \
		--data '{"show": "all", "hide": "Electronincs Door", "view": "Render_ebay", "focalLength": 200, "quality": "75", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_heater.png: obj/yammu.files.json
	mkdir -p Images && \
	$(SEND) --file $< \
		--jmespath "[?name == 'Assembly'].{open:id}" \
		--output $@
	$(SEND) --get /render \
		--data '{"show": "all", "hide": "Drawer", "view": "Render_heater", "focalLength": 200, "quality": "75", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_feeder.png: obj/yammu.files.json
	mkdir -p Images && \
	$(SEND) --file $< \
		--jmespath "[?name == 'Direct Drive x4'].{open:id}" \
		| $(SEND) --get /document --file -  && \
	$(SEND) --get /render \
		--data '{"view": "home", "focalLength": 200, "quality": "75", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_splitter.png: obj/yammu.files.json
	mkdir -p Images && \
	$(SEND) --file $< \
		--jmespath "[?name == 'Direct Drive x4'].{open:id}" \
		| $(SEND) --get /document --file -  && \
	$(SEND) --get /render \
		--data '{"view": "Render_Splitter", "focalLength": 200, "quality": "75", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/latch_lock.png: obj/yammu.files.json
	mkdir -p Images && \
	$(SEND) --file $< \
		--jmespath "[?name == 'Direct Drive x4'].{open:id}" \
		| $(SEND) --get /document --file -  && \
	$(SEND) --get /render \
		--data '{"view": "MotionStudy_Latch", "focalLength": 200, "quality": "75", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@

Images/render_cw2.png: obj/yammu.files.json
	mkdir -p Images && \
	$(SEND) --file $< \
		--jmespath "[?name == 'Stealthburner_CW2_Filament_Sensor_ECAS'].{open:id}" \
		| $(SEND) --get /document --file -  && \
	$(SEND) --get /render \
		--data '{"view": "home", "show": "all", "exposure": 8.2, "focalLength": 200, "quality": "75", "width": 400, "height": 400}' \
		--timeout 180 \
		--output $@


# obj/bom: obj/components.json
# 	mkdir -p $@ && \
# 	$(SEND) --file $< -x "$$.result[?(@.name =~ '(BHCS|ISO 7380-1)')]" --group 'name,.*M(\d+)\s*(x\s*\d+\.\d+\s*)?x\s*(\d+).*,M\1x\3 BHCS' --select 'name,count' --output $@/bhcs.json && \
# 	$(SEND) --file $< -x "$$.result[?(@.name =~ '(SHCS|DIN 912)')]"    --group 'name,.*M(\d+)\s*(x\s*\d+\.\d+\s*)?x\s*(\d+).*,M\1x\3 SHCS' --select 'name,count' --output $@/shcs.json && \
# 	$(SEND) --file $< -x "$$.result[?(@.name =~ 'Hex Nut')]"           --group 'name,.*M(\d+).*,M\1 Hex Nut'                               --select "name,count" --output $@/hex_nut.json && \
# 	$(SEND) --file $< -x "$$.result[?(@.name =~ 'Ballbearing')]"       --group 'name'                                                      --select "name,count" --output $@/ballbearing.json


dummy:
	

clean:
	cd FusionAddons/FusionHeadless && make clean && cd ../..
	rm -rf obj