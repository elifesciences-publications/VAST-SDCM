//CountCells_2D v1.1
//2018-03-05
//Copyright (c) 03/05/2017 Jason J Early
//The University of Edinburgh
/*
    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

var suffix, zPrefix, zMipPrefix, MIPZ, MIPX, usexMIP, output, xCoords, yCoords, thresholdX, gHeart, manualAdjust, advancedSelection, reuseROI, counting, manualCountAd, autoCountsV, autoCountsD, manualCountsD, manualCountsV, processedImages, countAutoD, countAutoV, intelthreshMode, setMinMax;
setBatchMode(true); // Enabling batch mode increases speed significantly
autoUpdate(false);

macro "CountCells_2D" {
// Set input directory
input = getDirectory("Folder containing \"Stitched\" and \"Output\" folders.");
MIPZ = input+"Stitched"+File.separator;
output = input+"Output"+File.separator;
if(!File.exists(output)){
	File.makeDirectory(output);
}
//List of preset variables
suffix = ".tif";
zPrefix = "Stitched_";
zMipPrefix = "Stitched_Max";
setMinMax = newArray(0, 1000);
// Create options dialog
Dialog.create("Set options for counting:");
Dialog.addNumber("1_Start_from_file#", 1);
Dialog.addNumber("2_Threshold for posterior maxima", 250);
Dialog.addCheckbox("3_Manual selection adjustment?", true);
Dialog.addNumber("4_Start_of_Spinal_cord?", 100);
Dialog.addCheckbox("5_Heart Marker Present?", false);
Dialog.addCheckbox("6_Count Dorsal?", true);
Dialog.addCheckbox("7_Count Ventral?", true);
Dialog.addCheckbox("8_Manual count adjustment?", true);
Dialog.addCheckbox("9_Advanced cell selection?", true);
Dialog.addCheckbox("10_Intelligent Threshold Adjustment?", false);
Dialog.show();
startNum = (Dialog.getNumber())-1;
thresholdX = Dialog.getNumber();
manualAdjust = Dialog.getCheckbox();
InitX = Dialog.getNumber();
gHeart = Dialog.getCheckbox();
counting1 = Dialog.getCheckbox();
counting2 = Dialog.getCheckbox();
counting = newArray(counting1, counting2);
manualCountAd = Dialog.getCheckbox();
advancedSelection = Dialog.getCheckbox();
intelThresh = Dialog.getCheckbox();
noiseSetD = NaN;
noiseSetV = NaN;
//Get thresholds for counting methods
if(counting[0]+counting[1]>0){
	Dialog.create("11_Set thresholds for counts");
	if(counting[0]==true) Dialog.addNumber("12_Dorsal threshold", 140);
	if(counting[1]==true) Dialog.addNumber("13_Ventral threshold", 200);
	Dialog.show();
	if(counting[0]==true) noiseSetD = Dialog.getNumber();
	if(counting[1]==true) noiseSetV = Dialog.getNumber();
}
if(intelThresh == true){
	intelthreshMode = true;
	Dialog.create("14_Intelligent threshold settings");
	Dialog.addNumber("15_How many test images?:", 5);
	Dialog.addNumber("16_Upper threshold:", 500);
	Dialog.addNumber("17_Lower threshold:", 50);
	Dialog.addNumber("18_Interval:", 10);
	Dialog.show();
	intelThreshNums = Dialog.getNumber();
	upperTemp = Dialog.getNumber();
	lowerTemp = Dialog.getNumber();
	intervalTemp = Dialog.getNumber();
	n = ((upperTemp-lowerTemp)/intervalTemp)+1;
	setThresh = newArray(n);
	for(i = 0; i < n; i++){
		setThresh[i] = lowerTemp + (i*intervalTemp);
	}
}
processFolder(MIPZ);
}

function processFolder(MIPZ){
	list = getFileList(MIPZ);
	for(i = 0; i < list.length; i++){
		if(!endsWith(list[i], suffix)){
			list = deleteRow(list, i);
			i = i-1;
		}
	}
	list = Array.sort(list);
	if(counting[0]+counting[1]>0){
	processedImages = newArray("File Name");
	autoCountsV = newArray("Ventral Auto");
	manualCountsV = newArray("Ventral Manual");
	autoCountsD = newArray("Dorsal Auto");
	manualCountsD = newArray("Dorsal Manual");
	}
	if(intelThresh == true){
		optiThresh = intelligentThresh(list);
		if(counting[0]==true) noiseSetD = optiThresh[0];
		if(counting[1]==true) noiseSetV = optiThresh[1];
	}
	timeStep = 1/list.length;
	for (i = startNum; i < list.length; i++) {
		timeProgress = i*timeStep;
		showProgress(timeProgress);
		showStatus(i + " of " + (list.length));
		if(endsWith(list[i], suffix)){
			processFile(MIPZ, output, list[i]);
			tabName = "Count-Summary_"+noiseSetD+"-"+noiseSetV+".csv";
			Array.show(tabName, processedImages, autoCountsD, manualCountsD, autoCountsV, manualCountsV);
			selectWindow(tabName);
			saveAs("Results", input+File.separator+tabName);
		}
	}
}

function processFile(input, output, file) {
	baseName1 = replace(file, zMipPrefix, "");
	baseName2 = replace(baseName1, suffix, "");
	zMipROI = baseName2+"_##_z.zip";
	run("Bio-Formats Windowless Importer", "open=["+input+file+"]");
	ID=getImageID();
	getVoxelSize(voxWidth, voxHeight, voxDepth, unit);
	if(unit=="pixels") setVoxelSize(0.849, 0.849, 1, "microns");//If no size information assume 3x3 binning 10X
	run("Subtract Background...", "rolling=50"); //To improve images where tiles are difference intensities.
	if (reuseROI==false){
		ROIWidth = newArray(65,25,40);
		ROIOffset = newArray(20,0,32.5);
		toUnscaled(ROIWidth, ROIOffset);
		plotROI(zMipROI, ROIWidth, ROIOffset, voxWidth, ID);
	}
	if (reuseROI==true){
		ROIWidth = newArray(NaN,NaN,NaN);
		plotROI(zMipROI, ROIWidth, NaN, voxWidth, ID);
	}
	countCells(file, zMipROI, ID);
	close("*.*");
	call("java.lang.System.gc");
}

function plotROI(ROIFile, ROIWidth, ROIOffset, scale, ID){ //Identify ventral spinal cord and specify regions of interest relative to it.
	oldROI = replace(ROIFile, "##", "Ventral");
	if(File.exists(output+oldROI)==1){
		roiManager("Reset");
		roiManager("Open", output+oldROI);
		roiManager("Select", 0);
		getSelectionCoordinates(xPoints, yPoints);
		roiManager("Reset");
	}
	else if(reuseROI==false){
	IncX=150*scale;
	xCoords = 0;
	yCoords = 0;
	selectImage(ID);
	ImYt=getHeight();
	ImXt=getWidth();
	xPoints = newArray(0);
	yPoints = newArray(0);
	pixInt = newArray(0);
	if(gHeart==true){
		profile = 0;
		run("Line Width...", "line="+ImYt+"");
		makeLine(0, (ImYt/2), ImXt, (ImYt/2));
		profile = getProfile();
		xMaxima = Array.findMaxima(profile, 30);
		MaxXArray = Array.trim(xMaxima, 1);
		heartLoc = MaxXArray[0];
		InitX = heartLoc+(160*scale);
	}
	LineNum = floor(((ImXt-InitX)/IncX)-1);
	for (i = 0; i < LineNum; i++) {
		profile = 0;
		n=i+1;
		SetX=InitX+(IncX*i);
		selectImage(ID);
		run("Line Width...", "line="+IncX+"");
		makeLine(SetX, ROIWidth[2], SetX, (ImYt*2/3));//Changed y1 from 0 to ROIWidth[2]
		profile = getProfile();
		yMaxima = Array.findMaxima(profile, 30);
		MaxYArray = Array.trim(yMaxima, 1);
		if (MaxYArray.length==0){
			MaxYArray = newArray(1);
			MaxYArray[0] = NaN;
		}
		MaxYInt =profile[(MaxYArray[0])]; 
		SetXArray = newArray(1);
		SetXArray[0] = SetX;
		xPoints = Array.concat(xPoints, SetXArray);
		yPoints = Array.concat(yPoints, (MaxYArray[0]+ROIWidth[2]));//Added ROIWidth[2] to MaxYArray to adjust for line not starting at y=0
		pixInt = Array.concat(pixInt, MaxYInt);
		close("Results");
		run("Select None");
	}
	for(i=0 ; i < yPoints.length ; i++) {
		if(isNaN(yPoints[i])==true){
			yPoints = deleteRow(yPoints, i);
			xPoints = deleteRow(xPoints, i);
			pixInt = deleteRow(pixInt, i);
			i = i-1;
		}
	}
	for(i=0 ; i < yPoints.length; i++) {
		if(i>5){
			if(pixInt[i]<thresholdX){
				yPoints = deleteRow(yPoints, i);
				xPoints = deleteRow(xPoints, i);
				pixInt = deleteRow(pixInt, i);
				i = i-1;
			}
		}
	}
	//Look for last cell
	if(xPoints.length > 4){ // Added xPoints.length exclusion
		subXTemp = Array.slice(xPoints, xPoints.length-4);
		subYTemp = Array.slice(yPoints, yPoints.length-4);
		xTemp = ImXt-10;
		Fit.doFit("Straight Line", subXTemp, subYTemp);
		yTemp = Fit.f(xTemp);
		subXTemp = Array.concat(subXTemp, xTemp);
		subYTemp = Array.concat(subYTemp, yTemp);
		selectImage(ID);
		run("Line Width...", "line="+ROIWidth[2]+"");
		makeSelection("polyline", subXTemp, subYTemp);
		run("Fit Spline", "straighten"); 
	   	getSelectionCoordinates(subXTemp, subYTemp); 
		profile = getProfile();
		xMaxima = Array.findMaxima(profile, 100);
		Array.sort(xMaxima);
		if(xMaxima.length == 0) xMaxima = newArray("0");//correct for no peaks
		xLast = subXTemp[xMaxima[xMaxima.length-1]];
		run("Select None");
		makeLine(xLast, (Fit.f(xLast)-(ROIWidth[2]/2)), xLast, (Fit.f(xLast)+(ROIWidth[2]/2)));
		profile = getProfile();
		yMaxima = Array.findMaxima(profile, 100);
		if(yMaxima.length == 0) yMaxima = Array.concat(yMaxima, (ROIWidth[2]/2));//correct for no peaks
		yLast = (Fit.f(xLast)-(ROIWidth[2]/2))+yMaxima[0];
	    setMinAndMax(setMinMax[0], setMinMax[1]);
		makePoint(xLast, yLast);
		xTemp = xLast-100;
		yTemp = Fit.f(xTemp);
		Fit.doFit("Straight Line", newArray(xTemp,xLast), newArray(yTemp,yLast));
		xFinal = xLast+(IncX/2);
		if(xFinal > ImXt) xFinal = ImXt;
		yFinal = Fit.f(xFinal);
		xPoints = Array.concat(xPoints, xFinal);
		yPoints = Array.concat(yPoints, yFinal);
	}
	}
	if(manualAdjust==true){
		roiManager("reset");
		selectImage(ID);
		run("Line Width...", "line=10");
		makeSelection("polyline", xPoints, yPoints);
	    setTool(5);
	    setMinAndMax(setMinMax[0], setMinMax[1]);
	    call("ij.gui.ImageWindow.setNextLocation", 0, 0);
	    setBatchMode("show");
//	    run("Scale to Fit");
	    call("ij.gui.ImageWindow.setNextLocation", 0, screenHeight/2);
		waitForUser("Adjust line and hit OK when finished");
		setBatchMode("hide");
		getMinAndMax(setMinMax[0], setMinMax[1]);
		getSelectionCoordinates(xPoints, yPoints);
	}
	if(reuseROI==false && xPoints.length>1){//Added xPoints.length exclusion
		roiManager("reset");
//		selectImage(ID);
		makeSelection("polyline", xPoints, yPoints); //Added makeSelection
		ROILineName = replace(ROIFile, "##", "Ventral");
		Roi.setName(ROILineName);
		roiManager("Add");
		roiManager("Save", output+ROILineName);
		roiManager("reset");
		close("ROI Manager");
		for (i=0; i < ROIWidth.length; i++) {
			ROIName = replace(ROIFile, "##", "0"+(i+1));
			Width = ROIWidth[i];
			Offset = ROIOffset[i];
			processArray(xPoints, yPoints, Width, Offset);
			if(i==2 || i==0) yCoords = taperDorsal(xCoords, yCoords, ROIWidth[2]/2);
			selectImage(ID);
			makeSelection("polygon", xCoords, yCoords);
			roiManager("reset");
			Roi.setName(ROIName);
			roiManager("Add");
			roiManager("Save", output+ROIName);
			roiManager("reset");
			close("ROI Manager");
		}
	}
	if(manualAdjust==true){
		for (i=0; i < ROIWidth.length; i++) {
			ROIName = replace(ROIFile, "##", "0"+(i+1));
			selectImage(ID);
			roiManager("Open", output+ROIName);
		}
	    setMinAndMax(setMinMax[0], setMinMax[1]);
	    roiManager("Show all without labels");
	    call("ij.gui.ImageWindow.setNextLocation", 0, 0);
	    setBatchMode("show");
//	    run("Scale to Fit");
	    call("ij.gui.ImageWindow.setNextLocation", 0, screenHeight/2);
		if(getBoolean("Is selection acceptable?")==false){
			roiManager("reset");
			setBatchMode("hide");
			plotROI(ROIFile, ROIWidth, ROIOffset, scale, ID);
		}
		else setBatchMode("hide");
	}
}

function countCells(file, ROIFile, ID){ //Produce and record cell counts in specified regions.
	ROIFileT = replace(ROIFile, "##", "01");
	ROIFileV = replace(ROIFile, "##", "02");
	ROIFileD = replace(ROIFile, "##", "03");
	roiManager("reset");
	if(File.exists(output+ROIFileT) && File.exists(output+ROIFileV) && File.exists(output+ROIFileD)){
	roiManager("Open", output+ROIFileT);
	roiManager("Open", output+ROIFileV);
	roiManager("Open", output+ROIFileD);
	countsFolder = "Counts_"+noiseSetD+"-"+noiseSetV+File.separator;
	if(!File.exists(output+File.separator+countsFolder)){
		File.makeDirectory(output+File.separator+countsFolder);
	}
	xVentral = newArray(0);
	yVentral = newArray(0);
	xDorsal = newArray(0);
	yDorsal = newArray(0);
	processedImages = Array.concat(processedImages, file);
	if(counting[0]==true){
		ROIName = replace(ROIFile, "##", "Counts");
		roiManager("Show None");
		if(intelthreshMode==true){
			countAutoD = newArray(0);
			noiseSetDTemp = noiseSetD;
			for(n=0; n<setThresh.length; n++){
				noiseSetD = setThresh[n];
				roiManager("Select", 2);
				if(advancedSelection == true) processCells(2,noiseSetD);
				else run("Find Maxima...", "noise="+noiseSetD+" output=[Point Selection]");
				getSelectionCoordinates(xDorsal, yDorsal);
				countAutoD = Array.concat(countAutoD, (xDorsal.length));
			}
			noiseSetD = noiseSetDTemp;
		}
		roiManager("Select", 2);
		Roi.getBounds(xPos, yPos, selWidth, selHeight);
		if(advancedSelection == true) processCells(2,noiseSetD);
		else run("Find Maxima...", "noise="+noiseSetD+" output=[Point Selection]");
		if((selectionType())==10){ //correcting for 0 counts
			getSelectionCoordinates(xDorsal, yDorsal);
			autoCountsD = Array.concat(autoCountsD, (xDorsal.length));
		}
		else{
			xDorsal = newArray(0);
			yDorsal = newArray(0);
			autoCountsD = Array.concat(autoCountsD, (0));
		}
		if(manualCountAd==true){
			setTool("multipoint");
	    	call("ij.gui.ImageWindow.setNextLocation", 0, 0);
			setBatchMode("show");
//      run("Set...", "zoom=200");
//			run("Set... ", "zoom=100 x="+xPos+" y="+yPos+"");
		    call("ij.gui.ImageWindow.setNextLocation", 0, screenHeight/2);
			waitForUser("Adjust points and hit OK when finished");
			setBatchMode("hide");
			if((selectionType())==10){ //correcting for 0 counts
			getSelectionCoordinates(xDorsal, yDorsal);
			}
			manualCountsD = Array.concat(manualCountsD, (xDorsal.length));
		}
		if(manualCountAd==false){
			manualCountsD = Array.concat(manualCountsD, NaN);
		}
		if((selectionType())!=10){
			xDorsal = newArray(0);
			yDorsal = newArray(0);
		}
		if((selectionType())==10){
			getSelectionCoordinates(xDorsal, yDorsal);
			roiManager("Add");
			roiManager("Save", output+countsFolder+ROIName);
		}
	}
	if(counting[1]==true){
		ROIName = replace(ROIFile, "##", "Counts");
		roiManager("Show None");
		if(intelthreshMode==true){
			countAutoV = newArray(0);
			noiseSetVTemp = noiseSetV;
			for(n=0; n<setThresh.length; n++){
				noiseSetV = setThresh[n];
				roiManager("Select", 1);
				if(advancedSelection == true) processCells(1,noiseSetV);
				else run("Find Maxima...", "noise="+noiseSetV+" output=[Point Selection]");
				getSelectionCoordinates(xVentral, yVentral);
				countAutoV = Array.concat(countAutoV, (xVentral.length));
			}
			noiseSetV = noiseSetVTemp;
		}
		roiManager("Select", 1);
		Roi.getBounds(xPos, yPos, selWidth, selHeight);
		if(advancedSelection == true) processCells(1,noiseSetV);
		else run("Find Maxima...", "noise="+noiseSetV+" output=[Point Selection]");
		if((selectionType())==10){ //correcting for 0 counts
			getSelectionCoordinates(xVentral, yVentral);
			autoCountsV = Array.concat(autoCountsV, (xVentral.length));
		}
		else{
			xVentral = newArray(0);
			yVentral = newArray(0);
		}
		if(manualCountAd==true){
			setTool("multipoint");
			call("ij.gui.ImageWindow.setNextLocation", 0, 0);
			setBatchMode("show");
//      run("Set...", "zoom=200");
//			run("Set... ", "zoom=150 x="+xPos+" y="+yPos+"");
		    call("ij.gui.ImageWindow.setNextLocation", 0, screenHeight/2);
			waitForUser("Adjust points and hit OK when finished");
			setBatchMode("hide");
			if((selectionType())==10){ //correcting for 0 counts
			getSelectionCoordinates(xVentral, yVentral);
			}
			manualCountsV = Array.concat(manualCountsV, (xVentral.length));
		}
		if(manualCountAd==false){
			manualCountsV = Array.concat(manualCountsV, NaN);
		}
		if((selectionType())!=10){
			xVentral = newArray(0);
			yVentral = newArray(0);
		}
		if((selectionType())==10){
			getSelectionCoordinates(xVentral, yVentral);
			roiManager("Add");
			roiManager("Save", output+countsFolder+ROIName);
		}
	}
	ROIName = replace(ROIFile, "##_z.zip", "Points.csv");
	if(File.exists(output+File.separator+countsFolder+ROIName)){
		ROIName = replace(ROIName, ".csv", "I.csv");
	}
	Array.show(ROIName, xVentral, yVentral, xDorsal, yDorsal);
	selectWindow(ROIName);
	saveAs("Results", output+File.separator+countsFolder+ROIName);
	run("Close");
	}
	else{
		processedImages = Array.concat(processedImages, file);
		if(counting[0]==true){
			autoCountsD = Array.concat(autoCountsD, "N/A");
			manualCountsD = Array.concat(manualCountsD, "N/A");
		}
		if(counting[1]==true){
			autoCountsV = Array.concat(autoCountsV, "N/A");
			manualCountsV = Array.concat(manualCountsV, "N/A");
		}
	}
	close(ID);
}

function processCells(roiNum, noise){ //Takes current point selection and produces single cell selections for each point, removes maxima identified to be non-cell like.
    ID = getImageID();
    run("Select None");
    run("Duplicate...", "Temp");
    ID2 = getImageID();
    roiManager("Select", roiNum);
    ImYt=getHeight();
    ImXt=getWidth();
    n = roiManager("count");
    run("Find Maxima...", "noise="+noise+" output=[Point Selection]");
    getSelectionCoordinates(xPoints, yPoints);
    Roi.setName("Raw Point Selection_"+roiNum);
    roiManager("Add");
    maxTemp = newArray((xPoints.length));
    xTemp = newArray((xPoints.length));
    yTemp = newArray((xPoints.length));
    for(i=0; i<xPoints.length; i++){
        maxTemp[i] = getPixel(xPoints[i], yPoints[i]);
        xTemp[i] = xPoints[i];
        yTemp[i] = yPoints[i];
    }
    xTemp2 = sortArrays(maxTemp, xTemp);
    yTemp2 = sortArrays(maxTemp, yTemp);
    maxTemp2 = Array.copy(maxTemp);
    Array.sort(maxTemp2);
    Array.reverse(xTemp2);
    Array.reverse(yTemp2);
    Array.reverse(maxTemp2);
    listXY = "";
    coordXY = "";
    //print("ROI Number"+"	"+"X"+"	"+"Y"+"	"+"Max"+"	"+"Min"+"	"+"Mean"+"	"+"Area"+"	"+"Width"+"	"+"Height");
    for(i=0; i<xTemp2.length; i++){
        selectImage(ID2);
        run("Select None");
        tempName = "Cell_"+IJ.pad(roiManager("count")-n,4)+"_"+xTemp2[i]+"_"+yTemp2[i];
        doWand(xTemp2[i], yTemp2[i], ((maxTemp2[i]/2)), "8-connected");
        if(selectionType()!=-1){
	        getStatistics(roiArea, roiMean, roiMin, roiMax);
	        Roi.getBounds(x1, y1, roiWidth, roiHeight);
	        locationTemp = ""+IJ.pad(x1, 4)+"-"+IJ.pad(y1, 4);
	        if(indexOf(listXY, locationTemp)==-1) roiExists = false;
	        else roiExists = true;
	        if(roiWidth<25 && roiArea<80 && roiArea>10 && roiExists==false){ // Selection criteria
	        //print((roiManager("count")-n)+"	"+xTemp2[i]+"	"+yTemp2[i]+"	"+roiMax+"	"+roiMin+"	"+roiMean+"	"+roiArea+"	"+roiWidth+"	"+roiHeight);
	            run("Enlarge...", "enlarge=1");
	            Roi.setName(tempName);
	            roiManager("Add");
	            run("Clear","slice");
	            listXY = ""+listXY+","+locationTemp;
	            coordXY = ""+coordXY+xTemp2[i]+","+yTemp2[i]+"\t";
	        }
    	}
    }
    tempArray = arraySequence(roiManager("count"));
    toSave = Array.slice(tempArray, n, roiManager("count"));
    roiManager("select", toSave);
    if(intelthreshMode==true) roiManager("Delete");
    else roiManager("Save Selected", output+File.separator+replace(file, suffix, "_Cells_"+roiNum+"_"+".zip"));
    selectImage(ID2);
    close();
    coordXY = split(coordXY, "\t");
    xPoints = newArray((coordXY.length));
    yPoints = newArray((coordXY.length));
    for(i=0; i<coordXY.length; i++){
        tempArray = split(coordXY[i], ",");
        xPoints[i] = tempArray[0];
        yPoints[i] = tempArray[1];
    }
    selectImage(ID);
    setTool("multipoint");
    makeSelection("point", xPoints, yPoints);
    Roi.setName("Processed Point Selection_"+roiNum);
}

function intelligentThresh(list){ // Find the optimum threshold to give the same cell count number as manual counts
	list = randomiseArray(list);
	optiThresh = newArray(2);
	optiThreshD = newArray(intelThreshNums);
	optiThreshV = newArray(intelThreshNums);
	for(i = 0; i < intelThreshNums; i++){
		manualCountAd = true;
		processFile(MIPZ, output, list[i]);
		if(counting[0]==1){
			countManD = manualCountsD[1];
			equation = "Exponential with Offset";
			Fit.doFit(equation, countAutoD, setThresh);
			optiThreshD[i] = Fit.f(countManD);
		}
		if(counting[1]==1){
			countManV = manualCountsV[1];
			equation = "Exponential with Offset";
			Fit.doFit(equation, countAutoV, setThresh);
			optiThreshV[i] = Fit.f(countManV);
		}
		processedImages = newArray("File Name");
		autoCountsV = newArray("Ventral Auto");
		manualCountsV = newArray("Ventral Manual");
		autoCountsD = newArray("Dorsal Auto");
		manualCountsD = newArray("Dorsal Manual");
	}
	optiThresh[0] = meanArray(optiThreshD);
	optiThresh[1] = meanArray(optiThreshV);
	manualCountAd = false;
	intelthreshMode = false;
	return optiThresh;
}

function processArray(X1, Y1, Width, Offset){ //Sets x and y Coordinates for selection using given offset and selection width
    xCoords = 0;
    yCoords = 0;
    Y2 = Array.copy(Y1);
    Y3 = Array.copy(Y1);
    Y3 = Array.reverse(Y3);
    for (i=0 ; i < Y1.length ; i++) {
        Y3[i] = Y3[i]+(Width/2)-Offset;
        Y2[i] = Y2[i]-(Width/2)-Offset;
    }
    yCoords = Array.concat(Y2,Y3);
    X2 = Array.copy(X1);
    Array.reverse(X2);
    xCoords = Array.concat(X1,X2);
}

function randomiseArray(array){ //Returns randomised copy of "array".
	randomNumbers = newArray((array.length));
	for(i=0; i<array.length; i++){
		randomNumbers[i] = random*100000000;
	}
	randomisedArray = sortArrays(randomNumbers, array);
	return randomisedArray;
}

function sortArrays(template, toSort){ //Sorts array "toSort" based on standard ranking of template
	rankTemp = Array.rankPositions(template);
	sorted = newArray((toSort.length));
	for(n=0; n<toSort.length; n++){
		sorted[n] = toSort[rankTemp[n]];
	}
	return sorted;
}

function arraySequence(n){
	array = newArray(n);
	for(i=0; i<n; i++){
		array[i] = i;
	}
	return array;
}

function deleteRow(array, n){
    arrayS = Array.slice(array, 0, n);
    arrayE = Array.slice(array, n+1, (array.length));
    array = Array.concat(arrayS, arrayE);
    return array;
}

function meanArray(array){
	n = array.length;
	for(i=0, arraySum=0; i<n; i++) arraySum = arraySum + array[i];
	return arraySum/n;
}

function taperDorsal(array1, array2, taper){ //Given a polygon selection, function linearly tapers top row towards the taper assumes equal and matched top and bottom points in polygon.
	xTemp = newArray(array1[0], array1[array1.length/2]);
	yTemp = newArray(0,taper);
	Fit.doFit("Straight Line", xTemp, yTemp);
	for(i = 0; i<array2.length/2; i++){
		array2[i] = array2[i]+Fit.f(array1[i]);
	}
	return array2;
}

function proximity(ROI, xPoints, yPoints){
	roiManager("reset");
	roiManager("Open", output+ROI);
	run("Fit Spline", "straighten");
	getSelectionCoordinates(xTemp, yTemp);
	yArray = newArray((xPoints.length));
	xArray = newArray((xPoints.length));
	Array.fill(distArray, NaN);
	length = newArray((xTemp.length));
	for(i=1; i<xTemp.length; i++){
		length[i] = sqrt(((xTemp[i]-xTemp[i-1])*(xTemp[i]-xTemp[i-1]))+((yTemp[i]-yTemp[i-1])*(yTemp[i]-yTemp[i-1]));
	}
	for(i=0; i<xPoints.length; i++){
		for(n=0; n<xTemp.length; n++){
			distTemp = sqrt(((xPoints[i]-xTemp[n])*(xPoints[i]-xTemp[n]))+((yPoints[i]-yTemp[n])*(yPoints[i]-yTemp[n]));
			if(distTemp < yArray[i]){
				yArray[i] = distTemp;
				xArray[i] = length[n];
			}
		}
	}
}