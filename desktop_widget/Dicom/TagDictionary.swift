// TagDictionary — names and VRs for the tags people look for, and names for common UIDs.
// Not the whole standard: the same table as dicom/index.html, with every sequence a
// viewer needs to find geometry in enhanced multi-frame files. Implicit VR files take
// their VRs from here.

import Foundation

enum TagDictionary {
    struct Entry {
        let vr: String
        let keyword: String
    }

    static let tags: [UInt32: Entry] = {
        var map: [UInt32: Entry] = [:]
        for line in source.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count == 3, let tag = UInt32(parts[0], radix: 16) else { continue }
            map[tag] = Entry(vr: String(parts[1]), keyword: String(parts[2]))
        }
        return map
    }()

    /// Overlay attributes repeat across groups 6000–601E, so they're matched by element.
    static let overlay: [UInt16: Entry] = [
        0x0010: Entry(vr: "US", keyword: "OverlayRows"), 0x0011: Entry(vr: "US", keyword: "OverlayColumns"),
        0x0022: Entry(vr: "LO", keyword: "OverlayDescription"), 0x0040: Entry(vr: "CS", keyword: "OverlayType"),
        0x0050: Entry(vr: "SS", keyword: "OverlayOrigin"), 0x0100: Entry(vr: "US", keyword: "OverlayBitsAllocated"),
        0x0102: Entry(vr: "US", keyword: "OverlayBitPosition"), 0x1500: Entry(vr: "LO", keyword: "OverlayLabel"),
        0x3000: Entry(vr: "OW", keyword: "OverlayData"),
    ]

    /// The VR to read an implicit VR element with.
    static func vr(for tag: UInt32) -> String {
        if let entry = tags[tag] { return entry.vr }
        let group = tag >> 16, element = UInt16(tag & 0xFFFF)
        if element == 0 { return "UL" }
        if group & 0xFF01 == 0x6000, let entry = overlay[element] { return entry.vr }
        if group & 1 == 1, (0x10...0xFF).contains(element) { return "LO" }
        return "UN"
    }

    static let uids: [String: String] = [
        "1.2.840.10008.1.2": "Implicit VR Little Endian",
        "1.2.840.10008.1.2.1": "Explicit VR Little Endian",
        "1.2.840.10008.1.2.1.99": "Deflated Explicit VR Little Endian",
        "1.2.840.10008.1.2.2": "Explicit VR Big Endian",
        "1.2.840.10008.1.2.4.50": "JPEG Baseline",
        "1.2.840.10008.1.2.4.51": "JPEG Extended (12-bit)",
        "1.2.840.10008.1.2.4.57": "JPEG Lossless",
        "1.2.840.10008.1.2.4.70": "JPEG Lossless SV1",
        "1.2.840.10008.1.2.4.80": "JPEG-LS Lossless",
        "1.2.840.10008.1.2.4.81": "JPEG-LS Near-Lossless",
        "1.2.840.10008.1.2.4.90": "JPEG 2000 Lossless",
        "1.2.840.10008.1.2.4.91": "JPEG 2000",
        "1.2.840.10008.1.2.4.201": "HTJ2K Lossless",
        "1.2.840.10008.1.2.4.203": "HTJ2K",
        "1.2.840.10008.1.2.5": "RLE Lossless",
        "1.2.840.10008.1.3.10": "Media Storage Directory Storage",
        "1.2.840.10008.5.1.4.1.1.1": "CR Image Storage",
        "1.2.840.10008.5.1.4.1.1.1.1": "Digital X-Ray Image Storage",
        "1.2.840.10008.5.1.4.1.1.1.2": "Digital Mammography Image Storage",
        "1.2.840.10008.5.1.4.1.1.2": "CT Image Storage",
        "1.2.840.10008.5.1.4.1.1.2.1": "Enhanced CT Image Storage",
        "1.2.840.10008.5.1.4.1.1.3.1": "Ultrasound Multi-frame Image Storage",
        "1.2.840.10008.5.1.4.1.1.4": "MR Image Storage",
        "1.2.840.10008.5.1.4.1.1.4.1": "Enhanced MR Image Storage",
        "1.2.840.10008.5.1.4.1.1.4.2": "MR Spectroscopy Storage",
        "1.2.840.10008.5.1.4.1.1.6.1": "Ultrasound Image Storage",
        "1.2.840.10008.5.1.4.1.1.7": "Secondary Capture Image Storage",
        "1.2.840.10008.5.1.4.1.1.11.1": "Grayscale Softcopy Presentation State",
        "1.2.840.10008.5.1.4.1.1.12.1": "X-Ray Angiographic Image Storage",
        "1.2.840.10008.5.1.4.1.1.20": "Nuclear Medicine Image Storage",
        "1.2.840.10008.5.1.4.1.1.66.4": "Segmentation Storage",
        "1.2.840.10008.5.1.4.1.1.88.11": "Basic Text SR",
        "1.2.840.10008.5.1.4.1.1.88.22": "Enhanced SR",
        "1.2.840.10008.5.1.4.1.1.88.33": "Comprehensive SR",
        "1.2.840.10008.5.1.4.1.1.128": "PET Image Storage",
        "1.2.840.10008.5.1.4.1.1.130": "Enhanced PET Image Storage",
        "1.2.840.10008.5.1.4.1.1.481.2": "RT Dose Storage",
        "1.2.840.10008.5.1.4.1.1.481.3": "RT Structure Set Storage",
    ]

    private static let source = """
00020000 UL FileMetaInformationGroupLength
00020001 OB FileMetaInformationVersion
00020002 UI MediaStorageSOPClassUID
00020003 UI MediaStorageSOPInstanceUID
00020010 UI TransferSyntaxUID
00020012 UI ImplementationClassUID
00020013 SH ImplementationVersionName
00020016 AE SourceApplicationEntityTitle
00020100 UI PrivateInformationCreatorUID
00020102 OB PrivateInformation
00041130 CS FileSetID
00041200 UL OffsetOfTheFirstDirectoryRecordOfTheRootDirectoryEntity
00041202 UL OffsetOfTheLastDirectoryRecordOfTheRootDirectoryEntity
00041212 US FileSetConsistencyFlag
00041220 SQ DirectoryRecordSequence
00041400 UL OffsetOfTheNextDirectoryRecord
00041410 US RecordInUseFlag
00041420 UL OffsetOfReferencedLowerLevelDirectoryEntity
00041430 CS DirectoryRecordType
00041500 CS ReferencedFileID
00041510 UI ReferencedSOPClassUIDInFile
00041511 UI ReferencedSOPInstanceUIDInFile
00041512 UI ReferencedTransferSyntaxUIDInFile
00080005 CS SpecificCharacterSet
00080008 CS ImageType
00080012 DA InstanceCreationDate
00080013 TM InstanceCreationTime
00080014 UI InstanceCreatorUID
00080016 UI SOPClassUID
00080018 UI SOPInstanceUID
00080020 DA StudyDate
00080021 DA SeriesDate
00080022 DA AcquisitionDate
00080023 DA ContentDate
0008002A DT AcquisitionDateTime
00080030 TM StudyTime
00080031 TM SeriesTime
00080032 TM AcquisitionTime
00080033 TM ContentTime
00080050 SH AccessionNumber
00080054 AE RetrieveAETitle
00080056 CS InstanceAvailability
00080060 CS Modality
00080064 CS ConversionType
00080068 CS PresentationIntentType
00080070 LO Manufacturer
00080080 LO InstitutionName
00080081 ST InstitutionAddress
00080090 PN ReferringPhysicianName
00080100 SH CodeValue
00080102 SH CodingSchemeDesignator
00080103 SH CodingSchemeVersion
00080104 LO CodeMeaning
00080201 SH TimezoneOffsetFromUTC
00081010 SH StationName
00081030 LO StudyDescription
00081032 SQ ProcedureCodeSequence
0008103E LO SeriesDescription
00081040 LO InstitutionalDepartmentName
00081048 PN PhysiciansOfRecord
00081050 PN PerformingPhysicianName
00081060 PN NameOfPhysiciansReadingStudy
00081070 PN OperatorsName
00081080 LO AdmittingDiagnosesDescription
00081090 LO ManufacturerModelName
00081110 SQ ReferencedStudySequence
00081111 SQ ReferencedPerformedProcedureStepSequence
00081115 SQ ReferencedSeriesSequence
00081120 SQ ReferencedPatientSequence
00081140 SQ ReferencedImageSequence
00081150 UI ReferencedSOPClassUID
00081155 UI ReferencedSOPInstanceUID
00081160 IS ReferencedFrameNumber
00081199 SQ ReferencedSOPSequence
00081250 SQ RelatedSeriesSequence
00082111 ST DerivationDescription
00082112 SQ SourceImageSequence
00082218 SQ AnatomicRegionSequence
00089007 CS FrameType
00089092 SQ ReferencedImageEvidenceSequence
00089121 SQ ReferencedRawDataSequence
00089123 UI CreatorVersionUID
00089205 CS PixelPresentation
00089206 CS VolumetricProperties
00089207 CS VolumeBasedCalculationTechnique
00089208 CS ComplexImageComponent
00089209 CS AcquisitionContrast
00100010 PN PatientName
00100020 LO PatientID
00100021 LO IssuerOfPatientID
00100030 DA PatientBirthDate
00100040 CS PatientSex
00101000 LO OtherPatientIDs
00101001 PN OtherPatientNames
00101010 AS PatientAge
00101020 DS PatientSize
00101030 DS PatientWeight
00101040 LO PatientAddress
00102000 LO MedicalAlerts
00102110 LO Allergies
00102160 SH EthnicGroup
001021B0 LT AdditionalPatientHistory
00104000 LT PatientComments
00120062 CS PatientIdentityRemoved
00120063 LO DeidentificationMethod
00180010 LO ContrastBolusAgent
00180015 CS BodyPartExamined
00180020 CS ScanningSequence
00180021 CS SequenceVariant
00180022 CS ScanOptions
00180023 CS MRAcquisitionType
00180024 SH SequenceName
00180025 CS AngioFlag
00180031 LO Radiopharmaceutical
00180050 DS SliceThickness
00180060 DS KVP
00180080 DS RepetitionTime
00180081 DS EchoTime
00180082 DS InversionTime
00180083 DS NumberOfAverages
00180084 DS ImagingFrequency
00180085 SH ImagedNucleus
00180086 IS EchoNumbers
00180087 DS MagneticFieldStrength
00180088 DS SpacingBetweenSlices
00180089 IS NumberOfPhaseEncodingSteps
00180090 DS DataCollectionDiameter
00180091 IS EchoTrainLength
00180093 DS PercentSampling
00180094 DS PercentPhaseFieldOfView
00180095 DS PixelBandwidth
00181000 LO DeviceSerialNumber
00181020 LO SoftwareVersions
00181030 LO ProtocolName
00181072 TM RadiopharmaceuticalStartTime
00181074 DS RadionuclideTotalDose
00181075 DS RadionuclideHalfLife
00181088 IS HeartRate
00181100 DS ReconstructionDiameter
00181110 DS DistanceSourceToDetector
00181111 DS DistanceSourceToPatient
00181120 DS GantryDetectorTilt
00181130 DS TableHeight
00181140 CS RotationDirection
00181150 IS ExposureTime
00181151 IS XRayTubeCurrent
00181152 IS Exposure
00181160 SH FilterType
00181164 DS ImagerPixelSpacing
00181170 IS GeneratorPower
00181190 DS FocalSpots
00181210 SH ConvolutionKernel
00181250 SH ReceiveCoilName
00181251 SH TransmitCoilName
00181310 US AcquisitionMatrix
00181312 CS InPlanePhaseEncodingDirection
00181314 DS FlipAngle
00181315 CS VariableFlipAngleFlag
00181316 DS SAR
00181318 DS dBdt
00185100 CS PatientPosition
00185101 CS ViewPosition
00189004 CS ContentQualification
00189005 SH PulseSequenceName
00189006 SQ MRImagingModifierSequence
00189042 SQ MRReceiveCoilSequence
00189049 SQ MRTransmitCoilSequence
00189073 FD AcquisitionDuration
00189082 FD EffectiveEchoTime
00189087 FD DiffusionBValue
00189089 FD DiffusionGradientOrientation
00189112 SQ MRTimingAndRelatedParametersSequence
00189114 SQ MREchoSequence
00189115 SQ MRModifierSequence
00189117 SQ MRDiffusionSequence
00189119 SQ MRAveragesSequence
00189125 SQ MRFOVGeometrySequence
00189345 FD CTDIvol
0020000D UI StudyInstanceUID
0020000E UI SeriesInstanceUID
00200010 SH StudyID
00200011 IS SeriesNumber
00200012 IS AcquisitionNumber
00200013 IS InstanceNumber
00200020 CS PatientOrientation
00200032 DS ImagePositionPatient
00200037 DS ImageOrientationPatient
00200052 UI FrameOfReferenceUID
00200060 CS Laterality
00200100 IS TemporalPositionIdentifier
00200105 IS NumberOfTemporalPositions
00200110 DS TemporalResolution
00201002 IS ImagesInAcquisition
00201040 LO PositionReferenceIndicator
00201041 DS SliceLocation
00204000 LT ImageComments
00209056 SH StackID
00209057 UL InStackPositionNumber
00209071 SQ FrameAnatomySequence
00209072 CS FrameLaterality
00209111 SQ FrameContentSequence
00209113 SQ PlanePositionSequence
00209116 SQ PlaneOrientationSequence
00209128 UL TemporalPositionIndex
00209153 FD NominalCardiacTriggerDelayTime
00209156 US FrameAcquisitionNumber
00209157 UL DimensionIndexValues
00209158 LT FrameComments
00209164 UI DimensionOrganizationUID
00209165 AT DimensionIndexPointer
00209167 AT FunctionalGroupPointer
00209221 SQ DimensionOrganizationSequence
00209222 SQ DimensionIndexSequence
00209421 LO DimensionDescriptionLabel
00280002 US SamplesPerPixel
00280004 CS PhotometricInterpretation
00280006 US PlanarConfiguration
00280008 IS NumberOfFrames
00280009 AT FrameIncrementPointer
00280010 US Rows
00280011 US Columns
00280030 DS PixelSpacing
00280034 IS PixelAspectRatio
00280100 US BitsAllocated
00280101 US BitsStored
00280102 US HighBit
00280103 US PixelRepresentation
00280106 US SmallestImagePixelValue
00280107 US LargestImagePixelValue
00280120 US PixelPaddingValue
00280301 CS BurnedInAnnotation
00281050 DS WindowCenter
00281051 DS WindowWidth
00281052 DS RescaleIntercept
00281053 DS RescaleSlope
00281054 LO RescaleType
00281055 LO WindowCenterWidthExplanation
00281101 US RedPaletteColorLookupTableDescriptor
00281102 US GreenPaletteColorLookupTableDescriptor
00281103 US BluePaletteColorLookupTableDescriptor
00281201 OW RedPaletteColorLookupTableData
00281202 OW GreenPaletteColorLookupTableData
00281203 OW BluePaletteColorLookupTableData
00282110 CS LossyImageCompression
00282112 DS LossyImageCompressionRatio
00282114 CS LossyImageCompressionMethod
00281056 CS VOILUTFunction
00283000 SQ ModalityLUTSequence
00283002 US LUTDescriptor
00283003 LO LUTExplanation
00283004 LO ModalityLUTType
00283006 US LUTData
00283010 SQ VOILUTSequence
00289110 SQ PixelMeasuresSequence
00289132 SQ FrameVOILUTSequence
00289145 SQ PixelValueTransformationSequence
00321032 PN RequestingPhysician
00321060 LO RequestedProcedureDescription
00321064 SQ RequestedProcedureCodeSequence
00324000 LT StudyComments
00400007 LO ScheduledProcedureStepDescription
00400009 SH ScheduledProcedureStepID
00400244 DA PerformedProcedureStepStartDate
00400245 TM PerformedProcedureStepStartTime
00400253 SH PerformedProcedureStepID
00400254 LO PerformedProcedureStepDescription
00400260 SQ PerformedProtocolCodeSequence
00400275 SQ RequestAttributesSequence
00400555 SQ AcquisitionContextSequence
00401001 SH RequestedProcedureID
00540016 SQ RadiopharmaceuticalInformationSequence
00540081 US NumberOfSlices
00541001 CS Units
00541102 CS DecayCorrection
00541300 DS FrameReferenceTime
00880140 UI StorageMediaFileSetUID
52009229 SQ SharedFunctionalGroupsSequence
52009230 SQ PerFrameFunctionalGroupsSequence
7FE00001 OV ExtendedOffsetTable
7FE00002 OV ExtendedOffsetTableLengths
7FE00008 OF FloatPixelData
7FE00009 OD DoubleFloatPixelData
7FE00010 OW PixelData
FFFAFFFA SQ DigitalSignaturesSequence
"""
}
