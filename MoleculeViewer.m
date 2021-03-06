
(* :Title: Molecule Viewer *)

(* :Author: J. M. *)

(* :Summary:
     This package implements an improved molecule viewer from Mathematica's default viewer,
     as well as providing a number of useful utility functions for obtaining and visualizing molecular models.
 *)

(* :Copyright:

     � 2017 by J. M. (pleasureoffiguring(AT)gmail(DOT)com)
     This work is free. It comes without any warranty, to the extent permitted by applicable law.
     You can redistribute and/or modify it under the terms of the WTFPL (http://www.wtfpl.net/)

 *)

(* :Package Version: 1.0 *)

(* :Mathematica Version: 11.0 *)

(* :History:
     1.0 initial release
*)

(* :Keywords:
     3D, chemistry, ChemSpider, JME, molecules, OpenBabel *)

(* :Limitations:
     currently limited handling of imported chemical file formats
*)

(* :Requirements:
     Requires Open Babel (http://openbabel.org/) and JME (http://www.molinspiration.com/jme/) to be installed.
     ChemSpider API key (http://www.chemspider.com/Register.aspx) needed for ChemSpider functionality.
*)   

BeginPackage["MoleculeViewer`"]
Unprotect[GetCACTUS, GetChemicalData, GetChemSpider, GetJMESMILES, LaunchJME, MoleculeViewer, RunOpenBabel];

(* usage messages *)

MoleculeViewer::usage = "MoleculeViewer[expr] displays a molecular model corresponding to expr. expr can be a file name of a chemical file format, a chemical name, a SMILES or an InChI string, or a list containing structural information."

GetChemicalData::usage = "GetChemicalData[expr] uses the built-in ChemicalData function to generate structural information suitable for MoleculeViewer."

GetChemSpider::usage = "GetChemSpider[expr] uses the ChemSpider API to generate structural information suitable for MoleculeViewer."

GetJMESMILES::usage = "GetJMESMILES[] extracts the SMILES of the chemical structure currently displayed in the JME applet.";

LaunchJME::usage = "LaunchJME[] launches an instance of the JME applet.";

RunOpenBabel::usage = "RunOpenBabel[expr] is an interface to OpenBabel, for generating structural information suitable for MoleculeViewer. expr can be a SMILES or an InChI string.";

Off[General::shdw];
If[ValueQ[Global`$ChemSpiderAPIToken],
    MoleculeViewer`$ChemSpiderAPIToken = Global`$ChemSpiderAPIToken];
Remove[Global`$ChemSpiderAPIToken];
On[General::shdw];
MoleculeViewer`$ChemSpiderAPIToken;

$JME; GetCACTUS;
(* for older versions *)
Highlighted; MemoryConstraint; PlotLegends;

(* error/warning messages *)

MoleculeViewer::badchem = "Invalid structural information given to MoleculeViewer.";
MoleculeViewer::is2d = "Two-dimensional coordinates detected; embedding to 3D."

GetChemSpider::token = "ChemSpider API key in $ChemSpiderAPIToken not detected or invalid. Please obtain one from http://www.chemspider.com/Register.aspx.";
InstallJME::nojme = "Java Molecular Editor not installed."
RunOpenBabel::nobab = "Open Babel not installed; please download from http://openbabel.org/.";

Begin["`Private`"]

$atoms = Array[ElementData[#, "Symbol"] &, 118];

$colorRules = Array[ElementData[#, "Symbol"] -> ElementData[#, "IconColor"] &, 118];

(* Pyykk�'s covalent radii; https://doi.org/10.1002/chem.200800987 *)
$elementCovalentRadii = {32, 46, 133, 102, 85, 75, 71, 63, 64, 67, 155, 139, 126, 116, 111, 
                                       103, 99, 96, 196, 171, 148, 136, 134, 122, 119, 116, 111, 110, 112, 
                                       118, 124, 121, 121, 116, 114, 117, 210, 185, 163, 154, 147, 138, 
                                       128, 125, 125, 120, 128, 136, 142, 140, 140, 136, 133, 131, 232, 
                                       196, 180, 163, 176, 174, 173, 172, 168, 169, 168, 167, 166, 165, 
                                       164, 170, 162, 152, 146, 137, 131, 129, 122, 123, 124, 133, 144, 
                                       144, 151, 145, 147, 142, 223, 201, 186, 175, 169, 170, 171, 172, 
                                       166, 166, 168, 168, 165, 167, 173, 176, 161, 157, 149, 143, 141, 
                                       134, 129, 128, 121, 122, 136, 143, 162, 175, 165, 157};

$sizeRules = Thread[Array[ElementData[#, "Symbol"] &, 118] -> N[$elementCovalentRadii/2]];

If[$VersionNumber >= 10.,

    translucentColorQ[col_] := ColorQ[col] && With[{l = Length[col]}, Switch[Head[col],
                                                                            GrayLevel, l == 2,
                                                                            RGBColor | Hue, l == 4,
                                                                            CMYKColor, l == 5,
                                                                            XYZColor | LABColor | LUVColor | LCHColor, l == 4,
                                                                            _, False] && 0 <= Last[col] < 1],
                                       
    translucentColorQ[col_] := With[{l = Length[col]}, Switch[Head[col],
                                                                                           GrayLevel, l == 2,
                                                                                           RGBColor | Hue, l == 4,
                                                                                           CMYKColor, l == 5,
                                                                                           _, False] && 0 <= Last[col] <1]
]

makeTranslucent[dir_] := If[translucentColorQ[dir] || Head[dir] === Opacity, dir, Opacity[0.6, dir]]

(* Hill system order for atoms *)
hillOrder["C", _] = 1;
hillOrder[_, "C"] = -1;
hillOrder["H", _] = 1;
hillOrder[_, "H"] = -1;
hillOrder[s1_, s2_] := Order[s1, s2];

SetAttributes[constrainedEvaluate, HoldFirst];
constrainedEvaluate[expr_, mem_, time_] := TimeConstrained[MemoryConstrained[expr, mem, $Failed], time, $Failed]

percentEncode[s_String] := If[$VersionNumber >= 10., URLEncode[s], 
                                             StringReplace[s, RegularExpression["[^\\w/\\?=:._~]"] :> 
                                                                  StringJoin["%", ToUpperCase[IntegerString[First[ToCharacterCode["$0"]], 16]]]]]

getNormal[mat_] := Flatten[Last[SingularValueDecomposition[Standardize[mat, Mean, 1 &], {-1}]]]

(* for XYZ format *)
inferBonds[vertexTypes_List, atomPositions_List, minDistance_: 40., bondTolerance_: 25., maxNeighbors_Integer: 8] /; Length[vertexTypes] == Length[atomPositions] :=
       Module[{atomP, curAtom, maxD, near, nearD, neighbors, nF, pos, rads},
                   pos = SetPrecision[atomPositions, MachinePrecision];
                   rads = N[vertexTypes /. Thread[$atoms -> $elementCovalentRadii]];
                   maxD = Max[rads] + bondTolerance;
  
                   nF = Nearest[pos -> Automatic];
                   neighbors = Function[idx,
                                                   curAtom = rads[[idx]];
                                                   near = DeleteCases[nF[pos[[idx]],
                                                                                      {maxNeighbors, curAtom + maxD}], idx];
                                                   atomP = pos[[idx]];
                                                   nearD = SquaredEuclideanDistance[#, atomP] & /@ pos[[near]];
                                                   Pick[near, MapThread[minDistance < #1 < #2 &,
                                                                                    {nearD, (curAtom + rads[[near]] + bondTolerance)^2}]]];
  
                   Union[Sort /@ Flatten[Array[Thread[# -> neighbors[#]] &, Length[vertexTypes]]]]]

(* validate input format for viewer *)
(* to do: validator for SMILES/InChI *)
validateChem[{vertexTypes_, edgeRules_, edgeTypes_, atomPositions_}] :=
           With[{dim = Dimensions[atomPositions], e = Length[edgeRules], v = Length[vertexTypes]},
                   (e == Length[edgeTypes] && v == First[dim]) &&
                   Complement[vertexTypes, $atoms] === {} && 
                   VectorQ[edgeRules, MatchQ[#, _Integer?Positive -> _Integer?Positive] &] && 
                   Complement[edgeTypes, {"Single", "Aromatic", "Double", "Triple"}] === {} &&
                   (MatrixQ[atomPositions, NumericQ] && 
                   MatchQ[Last[dim], 2 | 3])]

processChemicalFile[fileName_String, type : (_String | Automatic) : Automatic] := 
           Module[{atoms, bonds, ext, pos, prop, res},

                       If[! FileExistsQ[fileName], Return[$Failed]];

                       ext = type;
                       If[ext === Automatic,
                           ext = FileExtension[fileName];
                           If[ext === "", Return[$Failed]]];
                       ext = ToUpperCase[ext];

                       prop = Import[fileName, "Elements"];
                       If[prop === $Failed || 
                           FreeQ[prop, "VertexTypes" | "EdgeRules" | "EdgeTypes" | "VertexCoordinates"],
                           Return[$Failed]];

                       If[FreeQ[prop, "EdgeRules" | "EdgeTypes"],
                           (* xyz format *)
                           res = Import[fileName, {"XYZ", {"VertexTypes", "VertexCoordinates"}}];
                           If[res =!= $Failed,
                              {atoms, pos} = res;
                              bonds = inferBonds[atoms, pos];
                              {atoms, bonds, ConstantArray["Single", Length[bonds]], pos},
                              res],
                           (* normal mode *)
                           res = Import[fileName, {ext, {"VertexTypes", "EdgeRules", "EdgeTypes", "VertexCoordinates"}}];
                           If[res =!= $Failed && ext === "SDF", res = Transpose[res]];
                           res]]

testOpenBabel := testOpenBabel = Check[Import["!obabel -H", "Text"]; True, Message[RunOpenBabel::nobab]; False]

Options[RunOpenBabel] = {MemoryConstraint -> Automatic, Method -> Automatic, TimeConstraint -> Automatic};

RunOpenBabel[chem_String, opts : OptionsPattern[]] := Module[{incq, met, msg, out, pars, proc},

     If[! testOpenBabel, Return[$Failed]];

     pars = Switch[met = OptionValue[Method],
                          Automatic | "Minimize",
                          {"--minimize", "--crit 1e-7",(*"--newton",*)"--ff Ghemical", "--steps 2000"},
                          "Conformer",
                          {"--conformer", "--weighted", "--score energy", "--nconf 20"},
                          "Generate", {},
                          _, Message[RunOpenBabel::mthd, met, Automatic]; {"--minimize", "--crit 1e-7", "--ff Ghemical", "--steps 2000"}];
     incq = If[StringMatchQ[chem, "InChI*"], "-iinchi", ""];
     out = {"MOL", {"VertexTypes", "EdgeRules", "EdgeTypes", "VertexCoordinates"}};
     
     constrainedEvaluate[If[$VersionNumber >= 10.,
                                       proc = Check[RunProcess[{"obabel", incq, "-:" <> "\"" <> chem <> "\"", "-omol", "--gen3d", "-c", "-h"} ~Join~ pars],
                                                            Return[$Failed]];
                                       If[proc["ExitCode"] == 0, 
                                           ImportString[proc["StandardOutput"], out], 
                                           If[(msg = proc["StandardError"]) =!= "", Echo[msg], 
                                               Echo["OpenBabel exit code: " <> IntegerString[proc["ExitCode"]]]]; $Failed],
                                       Check[Import[StringJoin[Riffle[{"!obabel", incq, "-:" <> "\"" <> chem <> "\"", "-omol", "--gen3d", "-c", "-h"} ~Join~ pars, " "]], out], $Failed]],
                                   OptionValue[MemoryConstraint] /. Automatic -> 536870912 (* 512 MB *),
                                  OptionValue[TimeConstraint] /. Automatic -> 120 (* 2 min. *)]]

GetCACTUS[arg_String] := Module[{in, out, url},
     url = "https://cactus.nci.nih.gov/chemical/structure/``/file?format=sdf&get3d=true";
     in = StringReplace[If[StringMatchQ[arg, "InChI*"], arg, percentEncode[arg]], "+" -> "%20"];
     out = {"MOL", {"VertexTypes", "EdgeRules", "EdgeTypes", "VertexCoordinates"}};
     If[$VersionNumber >= 10., Import[StringTemplate[url][in], out], Import[ToString[StringForm[url, in]], out]]]

GetChemicalData[str_String, out : (Automatic | "SMILES" | "InChI") : Automatic] := Module[{chk, res},
     chk = ChemicalData[str, "StandardName"];
     If[chk === $Failed, Return[chk]];
     If[out === Automatic,
         res = Table[ChemicalData[str, prop],
                           {prop, {"VertexTypes", "EdgeRules", "EdgeTypes", "AtomPositions"}}];
	 If[FreeQ[res, ChemicalData],
             res = MapAt[If[$VersionNumber >= 9., QuantityMagnitude, Identity][#] &, res, {-1}];
             If[validateChem[res], res, $Failed], $Failed],
         ChemicalData[str, out]]]

GetChemSpider[str_String, out : (Automatic | "SMILES" | "InChI") : Automatic] := Module[{id, res},

     If[! ValueQ[$ChemSpiderAPIToken] || ! StringQ[$ChemSpiderAPIToken],
         Message[GetChemSpider::token]; Return[$Failed]];

     id = Quiet[Check[Import["http://www.chemspider.com/Search.asmx/SimpleSearch?token=" <> $ChemSpiderAPIToken <>
                                           "&query=" <> percentEncode[str], {"XML", "Plaintext"}], $Failed]];
     If[id =!= $Failed,
         If[out === Automatic,
             Import["http://www.chemspider.com/FilesHandler.ashx?type=str&3d=yes&id=" <> First[StringSplit[id, "\n"]],
                        {"MOL", {"VertexTypes", "EdgeRules", "EdgeTypes", "VertexCoordinates"}}],
             res = Quiet[Check[Import["http://www.chemspider.com/Search.asmx/GetCompoundInfo?token=" <> $ChemSpiderAPIToken <>
                                                     "&CSID=" <> First[StringSplit[id, "\n"]], {"XML", "Plaintext"}], $Failed]];
             If[res =!= $Failed, StringSplit[res, "\n"][[If[out === "SMILES", 4, 2]]],
                 $Failed]],
         $Failed]]

InstallJME[] := Module[{dir = FileNameJoin[{$UserBaseDirectory, "Applications", "JME", "Java"}],
                                    applet, url},
                                   applet = FileNameJoin[{dir, "JME.jar"}];
                                   url = "http://www.molinspiration.com/jme/doc/JME.jar";
                                   If[FileExistsQ[applet], True,
                                       CreateDirectory[dir];
                                       If[$VersionNumber >= 9.,
                                           Check[URLSave[url, applet]; True, False],
                                           Check[Utilities`URLTools`FetchURL[url, applet]; True,
                                           Message[InstallJME::nojme]; False]]]]

LaunchJME[] := JLink`JavaBlock[If[InstallJME[],
                                                    JLink`InstallJava[];
                                                    $JME = JLink`JavaNew["JME"];
                                                    JLink`AppletViewer[$JME, {}];
                                                    $JME, $Failed]]

GetJMESMILES[] := JLink`JavaBlock[$JME @ smiles[]]
                                                    
(* MoleculeViewer *)

Options[MoleculeViewer] = Sort[Join[{Background -> RGBColor[0., 43./255, 54./255], BaseStyle -> Automatic, Boxed -> False, ColorRules -> Automatic, 
                                                         Highlighted -> None, Lighting -> "Neutral", PlotLegends -> None, SphericalRegion -> True, Tooltip -> None, ViewPoint -> Automatic}, 
                                                       Select[Options[Graphics3D], FreeQ[#, Background | BaseStyle | Boxed | Lighting | SphericalRegion | ViewPoint] &]]];

SyntaxInformation[MoleculeViewer] = {"ArgumentsPattern" -> {_, OptionsPattern[MoleculeViewer]}};

MoleculeViewer[args___] := Block[{a, res},
                                                    a = System`Private`Arguments[MoleculeViewer[args], {1, 1}];
                                                    res /; a =!= {} && (res = iMoleculeViewer @@ Flatten[a, 1]) =!= $Failed && MatchQ[Head[res], Graphics3D | Legended]];

iMoleculeViewer[dat : {{_List, _List, _List, _List} ..}, opts___] := iMoleculeViewer[#, opts] & /@ dat

iMoleculeViewer[str_String, opts___] := Block[{res = $Failed},
 Quiet[Catch[Scan[Function[op, With[{r = op[str]}, If[r =!= $Failed, Throw[Set[res, r]]]]],
                            If[FileExistsQ[str], {processChemicalFile},
			        {RunOpenBabel, GetChemicalData, GetCACTUS, GetChemSpider}]]],
          {ChemicalData::notent, Import::fmterr, Utilities`URLTools`FetchURL::conopen, Utilities`URLTools`FetchURL::httperr}];
 iMoleculeViewer[res, opts]]

iMoleculeViewer[$Failed, opts___] := $Failed

iMoleculeViewer[{vertexTypes_, edgeRules_, edgeTypes_, atomPositions_}, opts : OptionsPattern[MoleculeViewer]] :=
 Block[{atomplot, atoms, bondlist, bondplot, bondtypes, cent, cRules, e, h, hiCol, hiSet, imat, ipos, leg, makebonds,
            myLegendFunction, nei, nrms, pos, res, skel, tips, v, view, vln, zpos},
  
          If[! validateChem[{vertexTypes, edgeRules, edgeTypes, atomPositions}], Message[MoleculeViewer::badchem]; Return[$Failed]];
  
          v = Length[vertexTypes]; e = Length[edgeTypes];
          pos = SetPrecision[atomPositions, MachinePrecision];
          view = OptionValue[ViewPoint] /.
                     Automatic -> 3.4 AffineTransform[RotationMatrix[Pi/20, {1, 0, 0}].
                                                                      RotationMatrix[-Pi/6, {0, 0, 1}]][getNormal[pos]];
          If[Last[Dimensions[pos]] == 2,
              Message[MoleculeViewer::is2d];
              view = {0, -Infinity, 0};
              pos = Insert[#, 0., 2] & /@ pos];
  
          cRules = Join[OptionValue[ColorRules] /. Automatic -> {}, $colorRules,
                               {_String -> RGBColor[211./255, 18./85, 26./51]}];

          atomplot = MapThread[{#1 /. cRules, Sphere[#2, #1 /. $sizeRules]} &, {vertexTypes, pos}];
  
          hiSet = OptionValue[Highlighted];
          If[hiSet =!= None,
              If[! ListQ[hiSet], hiSet = {hiSet}];
              hiCol = RGBColor[0.5, 1., 0., 0.6];
              If[VectorQ[hiSet, MatchQ[#, _Integer | _String] &], 
                  hiSet = Thread[hiSet -> hiCol]];
              hiSet = Function[l, MapAt[If[IntegerQ[#], {#}, #] &, l, {1}]] /@
                          Replace[hiSet, x : Except[_Rule | _RuleDelayed] :> (x -> hiCol), {1}];
              hiSet = DeleteCases[hiSet /. s_String :> Flatten[Position[vertexTypes, s]],
                                             HoldPattern[{} -> _] | HoldPattern[{} :> _]];
              atomplot = Fold[MapAt[Function[{l}, 
                                                               Join[l, {makeTranslucent[#2[[2]]], MapAt[1.2 # &, l[[-1]], -1]}]], #1, List /@ #2[[1]]] &, 
                                      atomplot, hiSet]];
  
          tips = OptionValue[Tooltip];
          If[MatchQ[tips, All | "Atoms"],
              atomplot = MapThread[Tooltip[#, 
                                                           Grid[{{Style["Atom no.", Bold], #2}, {Style["Element:", Bold], #3}, {Style["Coordinates:", Bold], #4}}, 
                                                                   Alignment -> {{Left, Left}}]] &,
              {atomplot, Range[v], vertexTypes, atomPositions}]];
  
          cent = Mean[pos];
  
          If[edgeRules =!= {} && edgeTypes =!= {},
              bondlist = List @@@ edgeRules;
              bondtypes = edgeTypes /. {"Single" -> 1, "Double" | "Aromatic" -> 2, "Triple" -> 3};

              skel = Graph[Range[v], UndirectedEdge @@@ bondlist];
              vln = VertexDegree[skel];
              imat = Quiet[Check[IncidenceMatrix[skel], $Failed, IncidenceMatrix::ninc], IncidenceMatrix::ninc];
              If[imat === $Failed, Return[$Failed]];

              ipos = GatherBy[imat["NonzeroPositions"], First];
              zpos = Position[imat.ConstantArray[1, e], 0];
              If[zpos =!= {}, zpos = List /@ PadRight[zpos, {Automatic, 2}]];
              ipos = #[[All, -1]] & /@ SortBy[Join[ipos, zpos], #[[1, 1]] &];

              nei = Union[Flatten[bondlist[[Union @@ ipos[[#]]]]]] & /@ bondlist;
              nrms = getNormal[pos[[#]]] & /@ nei;
              nrms *= Function[n, 2 UnitStep[Apply[Subtract, EuclideanDistance[cent, # n] & /@ {1, -1}]] - 1] /@ nrms;
   
              h = 2^(-3/2);
   
              makebonds[bid_, no_, mul_] := 
              Block[{bo = no, en = pos[[bid]], r = 12 - 2 mul, cl, d, del, mids, pr, tm},
                       del = Subtract @@ en; d = Norm[del]; del /= d;
                       cl = vertexTypes[[bid]] /. cRules;
                       mids = Range[0, 1, 1/(2 + 2 Boole[mul > 1])];
                       tm = Transpose[{1 - mids, mids}].en;

                       If[mul == 1,
                           (* single bond *)
                           Riffle[cl, Tube[#, r] & /@ Partition[tm, 2, 1]],
                           (* multiple bond *)
                           If[Chop[Abs[pr = bo.del]] != 0,
                               bo -= del pr; bo = Normalize[bo];
                               bo *= 2 UnitStep[Apply[Subtract, EuclideanDistance[cent, # bo] & /@ {1, -1}]] - 1];
                           bo *= h d; If[Max[vln[[bid]]] > 3, bo /= 2];
                           Table[Riffle[cl, Tube[BSplineCurve[#], r] & /@ 
                                            Partition[tm + ArrayPad[ConstantArray[RotationMatrix[2 Pi j/mul, del].bo, 3], {{1, 1}, {0, 0}}], 3, 2]],
                                    {j, 0, mul - 1}]]];
   
              bondplot = MapThread[makebonds, {bondlist, nrms, bondtypes}];
              If[MatchQ[tips, All | "Bonds"],
                  bondplot = MapThread[Tooltip[#, 
                                                               Grid[{{Style["Bond no.", Bold], #3}, {Style["Bond type:", Bold], ToLowerCase[#2]},
							                {Style["Bond length:", Bold], Row[{#4, " pm"}]}}, Alignment -> {{Left, Left}}]] &,
                                                    {bondplot, edgeTypes, Range[Length[edgeTypes]], 
                                                      Round[Apply[EuclideanDistance, pos[[#]]], 0.01] & /@ bondlist}]],
              (* no bonds *)
              bondplot = {}];
  
          res = Graphics3D[{atomplot, bondplot},
                                     FilterRules[Join[{opts}, Options[MoleculeViewer]] /.
                                                     {(BaseStyle -> Automatic) -> (BaseStyle -> Directive[CapForm["Butt"], Specularity[1, 50]]),
                                                       (ViewPoint -> Automatic) -> (ViewPoint -> view)}, 
                                                     Options[Graphics3D]]];
  
          If[$VersionNumber > 9.,
              leg = OptionValue[PlotLegends];
              atoms = Sort[DeleteDuplicates[vertexTypes], hillOrder];
              atoms = Apply[Sequence, {atoms /. cRules, atoms}];
              myLegendFunction = Framed[#, Background -> RGBColor[0.863, 0.863, 0.863],
	                                                  FrameMargins -> 0, FrameStyle -> None, RoundingRadius -> 5] &;

              Switch[leg,
                         Automatic | True | "Atoms",
                         Legended[res, SwatchLegend[atoms, 
                                                                     LabelStyle -> {Bold, 12, RGBColor[0.3, 0.3, 0.3]}, 
                                                                     LegendFunction -> myLegendFunction, LegendMarkerSize -> 15]],
                         _PointLegend | _SwatchLegend,
                         Legended[res, Replace[leg, Automatic | "Atoms" :> atoms, 1]],
                         Placed[_PointLegend | _SwatchLegend, _],
                         Legended[res, Replace[leg, Automatic | "Atoms" :> atoms, 2]],
                         None | False, res,
                         _, Legended[res, leg]],
              res]]

End[ ]

SetAttributes[{GetCACTUS, GetChemicalData, GetChemSpider, GetJMESMILES, LaunchJME, MoleculeViewer, RunOpenBabel}, ReadProtected];
Protect[GetCACTUS, GetChemicalData, GetChemSpider, GetJMESMILES, LaunchJME, MoleculeViewer, RunOpenBabel];

EndPackage[ ]