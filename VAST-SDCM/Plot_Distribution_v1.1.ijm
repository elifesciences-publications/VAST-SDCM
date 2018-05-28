//Plot_Distribution v1.1
//2018-05-28
//Copyright (c) 28/05/2018 Jason J Early
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

var suffix, pointsIn, scale, binData, bins, binInterval;

setBatchMode(true);

macro "Plot_Distribution"{
input = getDirectory("Input directory containing ventral line ROIs");
pointsIn = getDirectory("Input directory containing cell counts of interest");
Dialog.create("File type");
Dialog.addString("File suffix: ", "_Ventral_z.zip", 20);
Dialog.addNumber("Scale:", 0.8490076);
Dialog.show();
suffix = Dialog.getString();
scale = Dialog.getNumber();
newImage("Temp", "8-bit", 10000, 10000, 1);
Dialog.create("Bin settings");
Dialog.addNumber("Upper Limit:", 5000);
Dialog.addNumber("Lower Limit:", 0);
Dialog.addNumber("Interval:", 100);
Dialog.show();
upperLim = Dialog.getNumber();
lowerLim = Dialog.getNumber();
binInterval = Dialog.getNumber();
n = floor((upperLim-lowerLim)/binInterval);
mod =(upperLim-lowerLim)%binInterval;
if (mod!=0){
	n++;
	upperLim = lowerLim+(binInterval*n);
}
bins = newArray(n);
for(i = 0; i < n; i++){
	bins[i] = lowerLim + ((i+1)*binInterval);
	if(i==0) binData = "Bin Centres:, "+bins[i]-(binInterval/2);
	else binData = binData+","+bins[i]-(binInterval/2);
}
for(i = 0; i < n; i++){
	if(i==0) binData = binData+"\nImage Title, Region, "+lowerLim+"<=X<"+bins[i];
	else binData = binData+","+bins[i-1]+"<=X<"+bins[i];
}
processFolder(input);
close("*.*");
}

function processFolder(input) {
	list = getFileList(input);
	for (i = 0; i < list.length; i++) {
//		if(File.isDirectory(input + list[i]))
//			processFolder("" + input + list[i]);
		if(endsWith(list[i], suffix))
			processFile(input, list[i]);
	}
	File.saveString(binData, input+File.separator+"Bin-Data-analysis.csv");
}

function processFile(input, file) {
	baseName = replace(file, suffix, "");
	pointFile = baseName+"_Counts_z.zip";
	if(File.exists(input+File.separator+file)&&File.exists(pointsIn+File.separator+pointFile)){
    roiManager("reset");
    roiManager("Open", pointsIn+pointFile);
    regions = countROIs("Processed Point Selection_");
    for(r=0; r<regions; r++){
      roiManager("reset");
      roiManager("Open", pointsIn+pointFile);
      region = r+2;
      roiNum = getROI("Processed Point Selection_"+region);
  		binData = binData+"\n"+baseName+","+region;
  		outFile = proximity(pointFile, file, roiNum);
		File.saveString(outFile, pointsIn+File.separator+baseName+"_"+region+"_cell-analysis.csv");
    }
	}
}

function proximity(ROI1, ROI2, ROINumber){
	roiManager("reset");
	roiManager("Open", pointsIn+ROI1);
	roiManager("Select", ROINumber);
	getSelectionCoordinates(xPoints, yPoints);
	roiManager("reset");
	roiManager("Open", input+ROI2);
	roiManager("Select", 0);
	run("Fit Spline", "straighten");
	getSelectionCoordinates(xTemp, yTemp);
	yArray = newArray((xPoints.length));
	xArray = newArray((xPoints.length));
	Array.fill(yArray, 10000000);
	length = newArray((xTemp.length));
	for(i=1; i<xTemp.length; i++){
		length[i] = length[i-1]+sqrt(((xTemp[i]-xTemp[i-1])*(xTemp[i]-xTemp[i-1]))+((yTemp[i]-yTemp[i-1])*(yTemp[i]-yTemp[i-1])));
	}
	for(i=0; i<xPoints.length; i++){
		for(n=0; n<xTemp.length; n++){
			distTemp = sqrt(((xPoints[i]-xTemp[n])*(xPoints[i]-xTemp[n]))+((yPoints[i]-yTemp[n])*(yPoints[i]-yTemp[n])));
			if(distTemp < yArray[i]){
				yArray[i] = distTemp*scale;
				xArray[i] = length[n]*scale;
			}
		}
	}
	for(i=0; i<bins.length; i++){
		for(n=0, c=0; n<xArray.length; n++){
			if(xArray[n]>=(bins[i]-binInterval)&&(xArray[n]<bins[i])) c++;
		}
		binData = binData+","+c;
	}
	outFile = "X (Norm), Y (Norm), X (Orig), Y (Orig), Scale = "+scale+"microns";
	for(i=0; i<xPoints.length; i++){
		outFile = outFile+"\n"+xArray[i]+","+yArray[i]+","+xPoints[i]+","+yPoints[i];
	}
	return outFile;
}

function countROIs(prefix){
  roiTot = roiManager("count");
  for(i=0, t=0; i<roiTot; i++){
    roiManager("select", i);
    if(startsWith(Roi.getName, prefix)) t++;
  }
  return t;
}

function getROI(name){
  roiTot = roiManager("count");
  index = -1;
  for(i=0; i<roiTot; i++){
    roiManager("select", i);
    tempName = Roi.getName;
    if(matches(tempName, name)) index = i;
  }
  return index;
}
