/*****************************************************************************
* Author: Ganesh Shivaji Mhaske
* Date:  29 May 2024
* INFO: Parses a CSV file and adds training attendees to training campaigns.
******************************************************************************/
public class TrainingAttendeeCSVHandler {
    
    /**
     * Processes a CSV file to add training attendees.
     * 
     * @param csvAndAccountIdInputs List of CSVIdAndAccountIDWrapper instances containing CSV file content IDs and Account ID.
     * @return List containing the result of the operation ('SUCCESS' or 'ERROR').
     */
    @InvocableMethod(label='Process training attendee CSV')
    public static List<String> processCSVForTrainingAttendees(List<CSVIdAndAccountIDWrapper> csvAndAccountIdInputs){
        String resultStr = '';
        try{
            if(csvAndAccountIdInputs != null && csvAndAccountIdInputs.size()>0){
                Id CSVContentDocumentId = csvAndAccountIdInputs[0].csvFileContentIds[0];
                Id accountId = csvAndAccountIdInputs[0].accountId;
            
                ContentVersion contentVersionObj = [ SELECT Id, VersionData 
                                                     FROM ContentVersion 
                                                     WHERE ContentDocumentId =:CSVContentDocumentId ];
                    
                String completeCSVData = contentVersionObj.VersionData.toString();
                String[] csvFileLines = completeCSVData.split('\n');
                
                List<TrainingAttendeeWrapper> trainingAttendees = new List<TrainingAttendeeWrapper>();
                 for(Integer i=1;i<csvFileLines.size();i++){                   
                    String[] csvAttendeeLine = csvFileLines[i].trim().split(',');                    
                    TrainingAttendeeWrapper trainingAttendee = new TrainingAttendeeWrapper() ;
                    trainingAttendee.firstName = csvAttendeeLine[0] ;             
                    trainingAttendee.lastName = csvAttendeeLine[1];
                    trainingAttendee.trainingDate = Date.valueOf(csvAttendeeLine[2]);
                    trainingAttendee.trainingName = csvAttendeeLine[3];
                    trainingAttendee.email = csvAttendeeLine[4]?.ToLowerCase();
                                                                                               
                    trainingAttendees.add(trainingAttendee);  
                  }
                                
                resultStr = addAttendeesToTrainings(trainingAttendees, accountId);
            }else{
                resultStr = 'ERROR';
            }
        }catch(Exception e){
            System.debug('Exceptin at TrainingAttendeeCSVHandler.processCSVForTrainingAttendees(): '+e.getMessage());
            resultStr = 'ERROR';
        }
        
        return (new List<String>{resultStr});
    }
    
    /**
     * Processes attendees from a CSV and adds them to training campaigns.
     * 
     * @param attendees List of TrainingAttendeeWrapper instances.
     * @param accountId Account ID to associate new contacts with.
     * @return Status of the operation ('SUCCESS' or 'ERROR').
     * @throws InvalidCSVDataException if any attendee's email or lastName is null.
     */
    @TestVisible
    private static String addAttendeesToTrainings(List<TrainingAttendeeWrapper> attendees, Id accountId){
        Map<String, TrainingAttendeeWrapper> emailToAttendeeMap = new Map<String, TrainingAttendeeWrapper>();
        List<CampaignMember> campaignMembersToInsert = new List<CampaignMember>();
        List<String> emailsOfInsertedCampaignMembers = new List<String>();
        Map<String, Contact> emailToContactMap = new Map<String, Contact>();
        Map<String, Lead> emailToLeadMap = new Map<String, Lead>();
                
        for(TrainingAttendeeWrapper attendee: attendees){
            if(attendee.email == null || attendee.lastName == null){
                throw new InvalidCSVDataException();
            }
            emailToAttendeeMap.put(attendee.email, attendee);
        }
        
        createContactForNonExistingAttendees(emailToAttendeeMap, accountId);
        // Assuming these 2 trainigs will always be there
        Id BPMNTrainingId = [SELECT ID FROM Campaign WHERE Name = 'BPMN Training'].Id;
        Id DMNTrainingId =  [SELECT ID FROM Campaign WHERE Name = 'DMN Training'].Id;
        
        if(BPMNTrainingId == null || DMNTrainingId == null){
            return null;
        }
        
        for(Contact con: [SELECT Id, Email 
                         FROM Contact 
                         WHERE Email IN :emailToAttendeeMap.keySet()]){
            TrainingAttendeeWrapper attendee = emailToAttendeeMap.get(con.Email);
            if(attendee != null){
                CampaignMember cm  = getCampaignMember(attendee, con, 'Contact');                
                campaignMembersToInsert.add(cm);
            }
            
        }
        
        for(Lead lead: [SELECT Id, Email 
                         FROM Lead 
                         WHERE Email IN :emailToAttendeeMap.keySet()]){
            TrainingAttendeeWrapper attendee = emailToAttendeeMap.get(lead.Email);
            if(attendee != null){
                CampaignMember cm  = getCampaignMember(attendee, lead, 'Lead');                
                campaignMembersToInsert.add(cm);
            }
            
        }
                
        try{
                if(campaignMembersToInsert != null && campaignMembersToInsert.size()>0){
                    INSERT campaignMembersToInsert;
                }else{
                    return 'ERROR';
                }
         }catch(Exception e){
                   return 'ERROR';
         }
        
         return 'SUCCESS';
    }
    
    /**
     * Creates a CampaignMember for a given attendee based on their training name and type (Contact or Lead).
     * 
     * @param attendee TrainingAttendeeWrapper instance containing attendee details.
     * @param attendeeSObject SObject instance representing the attendee (Contact or Lead).
     * @param attendeeType String indicating the type of attendee ('Contact' or 'Lead').
     * @return A CampaignMember associated with the specified training campaign.
     */
    @TestVisible
    private static CampaignMember getCampaignMember(TrainingAttendeeWrapper attendee, SObject attendeeSObject, String attendeeType){
         Id trainingCampaignId;
        
         if(attendee.trainingName == 'BPMN Training'){
            trainingCampaignId = getTrainingCampaignId('BPMN Training');
         }else if(attendee.trainingName == 'DMN Training'){
            trainingCampaignId = getTrainingCampaignId('DMN Training');
         }
                
        CampaignMember cm = new CampaignMember();
        cm.CampaignId = trainingCampaignId;
        if(attendeeType == 'Contact'){
          cm.ContactId = ((Contact)attendeeSObject).Id;
        }else if(attendeeType == 'Lead'){
          cm.LeadId = ((Lead)attendeeSObject).Id;
        }
           
        return cm;
    }
    
    /**
     * Retrieves the Campaign ID for a given training name.
     * 
     * @param trainingName The name of the training campaign.
     * @return The ID of the training campaign, or null if not found.
     */
    @TestVisible
    private static Id getTrainingCampaignId(String trainingName){
        Campaign training = [SELECT ID FROM Campaign WHERE Name = :trainingName];
        if(training == null){
            return null;
        }
        
        return training.Id;
    }

    /**
     * Creates Contact records for attendees who do not already exist as Contacts or Leads.
     * 
     * @param emailToAttendeeMap Map of attendee emails to TrainingAttendeeWrapper instances.
     * @param accountId Account ID to associate new contacts with.
     */
    @TestVisible
    private static void createContactForNonExistingAttendees(Map<String, TrainingAttendeeWrapper> emailToAttendeeMap, Id accountId){
       Set<String> nonExistingAttendeesEmails = getNonExistingAttendeesEmails(emailToAttendeeMap.keySet());
       List<Contact> contactsToInsert = new List<Contact>();
        
        for(String attendeeEmail : nonExistingAttendeesEmails){
            if(emailToAttendeeMap.containsKey(attendeeEmail)){
                Contact con = new Contact();
                TrainingAttendeeWrapper attendee = emailToAttendeeMap.get(attendeeEmail);
                con.FirstName = attendee?.firstName;
                con.LastName = attendee?.lastName;
                con.Email = attendee?.email;
                con.AccountId = accountId;
                
                contactsToInsert.add(con);
            }
        }
        
        if(contactsToInsert != null && contactsToInsert.size()>0){
            INSERT contactsToInsert;
        }  
    }
    
    /**
     * Returns a set of emails for attendees that do not exist as Contacts or Leads in Salesforce.
     * 
     * @param attendeeEmails Set of attendee email addresses to check.
     * @return Set of email addresses that do not exist as Contacts or Leads.
     */
    @TestVisible
    private static Set<String> getNonExistingAttendeesEmails(Set<String> attendeeEmails){
        Set<String> existingAttendeesEmails = new Set<String>();
        Set<String> nonExistingAttendeesEmails = new Set<String>();
        
        List<Contact> ls = [SELECT Id, Email FROM Contact WHERE Email IN :attendeeEmails];
        List<Lead> ls2 = [SELECT Id, Email FROM Lead WHERE Email IN :attendeeEmails];            
        
        for(Contact con: [SELECT Id, Email FROM Contact WHERE Email IN :attendeeEmails]){
            existingAttendeesEmails.add(con.Email.toLowercase());
        }
        
        for(Lead lead: [SELECT Id, Email FROM Lead WHERE Email IN : attendeeEmails AND Email NOT IN :existingAttendeesEmails]){
            existingAttendeesEmails.add(lead.Email.toLowercase());
        }
                
        for(String attendeeEmail : attendeeEmails){
            if(!existingAttendeesEmails.contains(attendeeEmail.toLowerCase())){
                nonExistingAttendeesEmails.add(attendeeEmail);
            }
        }
        
        return nonExistingAttendeesEmails;
    }
    
     /**
     * Wrapper class to hold CSV file content and account record ID.
     * This wrapper class is necessary because invocable methods can only accept a single input parameter.
     */
    public class CSVIdAndAccountIDWrapper {
        @InvocableVariable(required=true)
        public List<Id> csvFileContentIds;
        
        @InvocableVariable(required=true)
        public Id accountId;
    }
    
    public class TrainingAttendeeWrapper{
        String firstName;
        String lastName;
        Date trainingDate;
        String trainingName;
        String email;
    }
    
    private class InvalidCSVDataException extends Exception {}
  
}