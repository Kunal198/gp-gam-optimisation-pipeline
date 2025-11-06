##### JJCode: 11/07/2017
###############################################################################################
###############################################################################################
###############################################################################################
###############################################################################################
#####
## source("/nfs/see-fs-01_users/earjsj/CSSP/UKCA_LargePPE_Jan15/EmulationSA_Codes/JJCode_RegionalSyntheticConstraintApplication/JJCode_EmPred_LargeSample.r")
#####
###############################################################################################
###############################################################################################
#####
## Function to apply 'predict.km()' to a very large set of input combinations... This:
##  -> splits up the input combinations matrix into more managable smaller chunks, 
##  -> applies predict.km() to each chunk individually 
##  -> saves the $mean output each time and then puts it back together into a large vector 
##      to return
##  -> Also allows for sd to be collated too... 
##  -> If want lower95 and upper95, code will need adapting...
#####
###############################################################################################
#####
JJCode_PredictFromEm_UsingLargeSample<-function(EmModIn,LargeSampInputCombs,nPredBreakVal,PredMean=TRUE,PredSD=FALSE,Pred95CIs=FALSE)
{
  nPredTotal<-dim(LargeSampInputCombs)[1]
#####
## Make the vector with the row values over which to break the inputs matrix for the individual 
##  prediction sets...
#####
  BreakSeq<-seq(from=0,to=nPredTotal,by=nPredBreakVal)
  nBreakVals<-length(BreakSeq)
  if(BreakSeq[nBreakVals]<nPredTotal){
    BreakSeq<-c(BreakSeq,nPredTotal)
    nBreakVals<-length(BreakSeq)
  }
  nBreaks<-nBreakVals-1
#####
## Make an indicator variable to see if the general (most likely) case of predicting the only
##  the emulator mean is required... 
##   -> 'PredictMeanOnly = 1' if yes, and 'PredictMeanOnly = 0' if no...
#####
  if(PredMean==TRUE & PredSD==FALSE & Pred95CIs==FALSE){
     PredictMeanOnly<-1
   }else{
     PredictMeanOnly<-0
   }
#####
## Set up the storage vectors for predictions:
#####
  if(PredictMeanOnly==1){
     PredMeanVec<-NULL
  }else{
    if(PredMean==TRUE){
      PredMeanVec<-NULL
    }
    if(PredSD==TRUE){
      PredSDVec<-NULL
    }
    if(Pred95CIs==TRUE){
      PredL95Vec<-NULL
      PredU95Vec<-NULL
    }
  }
#####
## Obtain the emulator prediction for each subset of the sample... and place into the corresponding 
##  vectors in order of computation...
#####
  if(PredictMeanOnly==1){
    for(kt in 1:nBreaks){
      rowStartVal<-BreakSeq[kt]+1
      rowEndVal<-BreakSeq[(kt+1)]
      SamplePredOutput<-predict.km(EmModIn,LargeSampInputCombs[rowStartVal:rowEndVal,],"UK",se.compute=TRUE,light.return=TRUE,checkNames=FALSE)$mean
      PredMeanVec<-c(PredMeanVec,SamplePredOutput)
    }
  }else{
    for(kt in 1:nBreaks){
      rowStartVal<-BreakSeq[kt]+1
      rowEndVal<-BreakSeq[(kt+1)]
      SamplePredOutput<-predict.km(EmModIn,LargeSampInputCombs[rowStartVal:rowEndVal,],"UK",se.compute=TRUE,light.return=TRUE,checkNames=FALSE)
      if(PredMean==TRUE){
        PredMeanVec<-c(PredMeanVec,SamplePredOutput$mean)
      }
      if(PredSD==TRUE){
        PredSDVec<-c(PredSDVec,SamplePredOutput$sd)
      }
      if(Pred95CIs==TRUE){
        PredL95Vec<-c(PredL95Vec,SamplePredOutput$lower95)
        PredU95Vec<-c(PredU95Vec,SamplePredOutput$upper95)
      }
    }
  }
#####
## Return the relevant bits back from the function...
#####
  ReturnList<-list()
  if(PredictMeanOnly==1){
    ReturnList$mean<-PredMeanVec
  }else{
    if(PredMean==TRUE){
      ReturnList$mean<-PredMeanVec
    }
    if(PredSD==TRUE){
      ReturnList$sd<-PredSDVec
    }
    if(Pred95CIs==TRUE){
      ReturnList$lower95<-PredL95Vec
      ReturnList$upper95<-PredU95Vec
    }
  }
  return(ReturnList)
}
#####
###############################################################################################
###############################################################################################
#####
## TEST: Run on Europe CCN Emulator and test stacked MLHS...
#####
#  source("/nfs/see-fs-01_users/earjsj/CSSP/UKCA_LargePPE_Jan15/EmulationSA_Codes/JJCode_RegionalSyntheticConstraintApplication/JJCode_MakeStackedMLHS_ByDist.r")
#  system.time(JJTestSampM<-JJCode_MakeStackedMLHSsample_ByDist(nStack=10,nPerSamp=1000,nPar=27,PPEname="27aeratm",MargDistList=UKCA27aeratmPPE_DistList,MargDistParsTab=DistParsTabIn,InputNames=InputNames_UKCA27aeratmPPE,SourceLibs=TRUE,RandomSamp=FALSE))
###
#  JJP_allatonce<-predict.km(EmModValidationList_CCN0p2_VL9_JUL_2008_27aeratm_R8[[3]],JJTestSampM,"UK",se.compute=TRUE,light.return=TRUE,checkNames=FALSE)
#  JJP_splitFn_MeanOnly<-JJCode_PredictFromEm_UsingLargeSample(EmModIn=EmModValidationList_CCN0p2_VL9_JUL_2008_27aeratm_R8[[3]],LargeSampInputCombs=JJTestSampM,nPredBreakVal=1000,PredMean=TRUE,PredSD=FALSE,Pred95CIs=FALSE)
#  JJP_splitFn_All<-JJCode_PredictFromEm_UsingLargeSample(EmModIn=EmModValidationList_CCN0p2_VL9_JUL_2008_27aeratm_R8[[3]],LargeSampInputCombs=JJTestSampM,nPredBreakVal=1000,PredMean=TRUE,PredSD=TRUE,Pred95CIs=TRUE)
#####
###############################################################################################
###############################################################################################
###############################################################################################
###############################################################################################
#####

